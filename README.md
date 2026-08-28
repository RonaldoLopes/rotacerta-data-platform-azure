# Azure Data Factory na Prática — RotaCerta Logística

Projeto de estudo de engenharia de dados construído **100% com Azure Data Factory** (sem Databricks), cobrindo desde o provisionamento de infraestrutura até um pipeline de CI/CD completo com GitHub Actions.

Baseado na apostila **"Azure Data Factory na Prática — Edição Engenheiro"** (90 páginas, 15 módulos + apêndices).

---

## Índice

- [Visão geral](#visão-geral)
- [Arquitetura](#arquitetura)
- [Cenário: RotaCerta Logística](#cenário-rotacerta-logística)
- [Pré-requisitos](#pré-requisitos)
- [Estrutura do repositório](#estrutura-do-repositório)
- [Infraestrutura (Terraform)](#infraestrutura-terraform)
- [Linked Services e Datasets](#linked-services-e-datasets)
- [Pipelines de ingestão (Bronze)](#pipelines-de-ingestão-bronze)
- [Transformação (Silver/Gold) com Mapping Data Flows](#transformação-silvergold-com-mapping-data-flows)
- [Orquestração e controle de fluxo](#orquestração-e-controle-de-fluxo)
- [Parametrização](#parametrização)
- [Triggers](#triggers)
- [Git Integration e CI/CD](#git-integration-e-cicd)
- [Monitoramento e alertas](#monitoramento-e-alertas)
- [Segurança](#segurança)
- [Custos](#custos)
- [Consumo com Synapse Serverless SQL](#consumo-com-synapse-serverless-sql)
- [Troubleshooting](#troubleshooting)
- [ADF vs. Databricks](#adf-vs-databricks)
- [Referências](#referências)

---

## Visão geral

Este projeto simula o dia a dia de um time de engenharia de dados que precisa consolidar fontes heterogêneas (banco relacional, API REST e arquivos CSV) em um Data Lake organizado em camadas (Bronze/Silver/Gold), usando **apenas recursos nativos do ADF** — Copy Data para ingestão e Mapping Data Flows para transformação, sem nenhuma linha de PySpark/Scala.

Todo o factory é versionado no Git (GitHub), com um fluxo de feature branch → Pull Request → Publish → deploy automatizado via GitHub Actions.

**Stack:** Azure Data Factory · Azure Data Lake Storage Gen2 · Azure SQL Database (Serverless) · Azure Key Vault · Terraform · GitHub Actions · Azure Synapse Analytics (SQL Serverless, opcional)

## Arquitetura

```
                    ┌─────────────────────────────────────────┐
                    │            Azure Data Factory              │
                    │                                             │
  Azure SQL DB ───▶│  Copy Data  ──▶  Bronze (raw)              │
  API REST     ───▶│  Copy Data  ──▶  Bronze (raw)              │
  CSV (Blob)   ───▶│  Copy Data  ──▶  Bronze (raw)              │
                    │                     │                       │
                    │                     ▼                       │
                    │  Mapping Data Flow ──▶  Silver (limpo)     │
                    │                     │                       │
                    │                     ▼                       │
                    │  Mapping Data Flow ──▶  Gold (agregado)    │
                    └─────────────────────────────────────────┘
                                      │
                                      ▼
                    Azure Data Lake Storage Gen2 (landing/bronze/silver/gold)
                                      │
                                      ▼
                    Synapse SQL Serverless (view externa) ──▶ Power BI
```

## Cenário: RotaCerta Logística

Empresa fictícia de entregas de última milha, com três fontes de dados:

| Fonte | Tipo | Conteúdo |
|---|---|---|
| **Pedidos e entregas** | Azure SQL Database | `dbo.Pedidos` (cliente, região, transportadora, datas prevista/real, valor do frete, status) |
| **Clima** | API REST pública (Open-Meteo) | Temperatura, precipitação por região (5 regiões do Brasil) |
| **Faturas de transportadoras** | CSV em Blob (`landing/faturas/`) | Custo repassado por entrega, por transportadora parceira |

**Objetivo de negócio:** calcular, por região, o custo médio por entrega, o percentual de atrasos e a correlação com condições climáticas — resultado final materializado em `gold/kpi_entregas/`.

## Pré-requisitos

- Assinatura Azure ativa
- Conta GitHub
- [Terraform](https://developer.hashicorp.com/terraform) instalado localmente
- [Azure CLI](https://learn.microsoft.com/cli/azure/) instalado e autenticado (`az login`)
- Editor de código (VS Code recomendado)

⚠️ **Atenção a custos:** Mapping Data Flows usam um cluster Spark gerenciado cobrado por vCore-hora enquanto ativo — ver seção [Custos](#custos).

## Estrutura do repositório

```
rotacerta-data-platform/
├── .github/
│   └── workflows/
│       └── ci-cd-adf.yml
├── infra/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── pipeline/           # sincronizado automaticamente pelo Git integration do ADF
├── dataset/
├── linkedService/
├── dataflow/
├── trigger/
├── factory/
├── scripts/
│   ├── seed_pedidos.sql
│   └── gerar_faturas.py
├── package.json
└── README.md
```

## Infraestrutura (Terraform)

Provisiona: Resource Group, Storage Account (ADLS Gen2, containers `landing`/`bronze`/`silver`/`gold`), Azure SQL Server + Database (Serverless, auto-pause), Key Vault, Data Factory (Managed Identity), e os role assignments necessários (`Storage Blob Data Contributor`, acesso de leitura ao Key Vault).

```bash
cd infra
terraform init
terraform plan -var="sql_admin_password=SuaSenhaForte123!"
terraform apply -var="sql_admin_password=SuaSenhaForte123!"
```

Outputs relevantes: `storage_account_name`, `data_factory_name`, `sql_server_fqdn`, `key_vault_name`.

## Linked Services e Datasets

| Linked Service | Tipo | Autenticação |
|---|---|---|
| `LS_ADLS_RotaCerta` | ADLS Gen2 | System Assigned Managed Identity |
| `LS_SQL_Pedidos` | Azure SQL Database | Connection string via Key Vault |
| `LS_API_Clima` | HTTP | Anônima |
| `LS_KeyVault_RotaCerta` | Key Vault | System Assigned Managed Identity |

Datasets: `DS_SQL_Pedidos`, `DS_API_Clima`, `DS_Landing_Faturas`, e três **datasets genéricos parametrizados** (`DS_Bronze_Generico`, `DS_Silver_Generico`, `DS_Gold_Generico`) reutilizados em todas as camadas via parâmetros `nomeContainer`/`nomePasta`.

## Pipelines de ingestão (Bronze)

| Pipeline | Padrão usado |
|---|---|
| `pl_bronze_pedidos` | Copy Data simples (SQL → Parquet) |
| `pl_bronze_clima` | `ForEach` sequencial sobre 5 regiões, chamando a API dinamicamente |
| `pl_bronze_faturas` | `Get Metadata` (lista arquivos) + `ForEach` (copia cada CSV → Parquet) |

Todas as atividades Copy Data usam **fault tolerance** (`Skip incompatible rows`) e **retry policy** (3 tentativas, 30s).

## Transformação (Silver/Gold) com Mapping Data Flows

| Data Flow | Transformações |
|---|---|
| `df_silver_pedidos` | Derived Column (padronização, cálculo de atraso), Filter, Window (dedup) |
| `df_silver_clima` | Derived Column, Select |
| `df_silver_faturas` | Derived Column, Aggregate (soma por pedido) |
| `df_gold_kpi_entregas` | Join (pedidos + faturas + clima) → Aggregate por região (custo médio, % atraso, temperatura média) |

Executados em sequência pelo pipeline `pl_silver_gold`. Requer **Data Flow Debug** ligado durante desenvolvimento — **desligar ao final da sessão** (custo).

## Orquestração e controle de fluxo

Pipeline mestre `pl_master_rotacerta`:

```
Lookup (checa transportadoras inativas)
   │
If Condition (notifica via Web Activity se houver)
   │
Execute Pipeline (bronze_pedidos) ─┐
Execute Pipeline (bronze_clima)   ─┼─▶ Execute Pipeline (silver_gold)
Execute Pipeline (bronze_faturas) ─┘        │
                                             ▼
                                   Fail (se silver_gold falhar)
```

Padrões usados: `Execute Pipeline` (modularização), `Lookup`, `If Condition`, `Fail` explícito, dependências `Success` vs. `Completed`.

## Parametrização

- **Parâmetros de pipeline:** ex. `dataReferencia` (carga incremental com watermark de 7 dias).
- **Global Parameters:** ex. `ambienteAtual` (dev/test/prd), acessível de qualquer pipeline.
- **Expressões dinâmicas:** `@pipeline().parameters.X`, `@item()`, `@activity('Nome').output`, `@pipeline().RunId`, `@utcnow()`.

## Triggers

| Trigger | Tipo | Uso |
|---|---|---|
| `trg_diario_rotacerta` | Schedule | Execução diária às 06:00 |
| `trg_tumbling_pedidos` | Tumbling Window | Janelas sequenciais com suporte a backfill e dependência entre triggers |
| `trg_evento_novo_arquivo_fatura` | Storage Event | Dispara ao chegar novo CSV em `landing/faturas/` (requer Event Grid) |

**Todos mantidos desativados** por padrão em ambiente de estudo (custo/previsibilidade).

## Git Integration e CI/CD

- **Collaboration branch:** `main` (JSONs de trabalho, salvos a cada alteração no Studio)
- **Publish branch:** `adf_publish` (templates ARM gerados automaticamente ao clicar **Publish**)
- **Fluxo:** feature branch → Pull Request → merge em `main` → Publish → `adf_publish` atualizada → GitHub Actions faz deploy

```yaml
# .github/workflows/ci-cd-adf.yml (resumo)
on:
  pull_request: { branches: [main] }   # roda validação
  push: { branches: [adf_publish] }    # roda deploy
```

Usa o pacote `@microsoft/azure-data-factory-utilities` para validar/exportar o ARM template. Secrets necessários no GitHub: `AZURE_SUBSCRIPTION_ID`, `AZURE_CREDENTIALS` (Service Principal).

## Monitoramento e alertas

- **Monitor** do ADF Studio: Pipeline runs, Trigger runs, Activity runs (visão Gantt).
- **Rerun from failed activity** para retomar execuções sem reprocessar tudo.
- **Diagnostic settings** → Log Analytics Workspace (retenção além dos 45 dias padrão, consultas KQL).
- **Azure Monitor Alerts** com Action Group (e-mail em caso de `Failed pipeline runs`).

## Segurança

- **Managed Identity** em vez de chaves/senhas em todos os Linked Services possíveis.
- Segredos sempre via **Key Vault**, nunca em texto plano em queries/expressões.
- **RBAC** com princípio do menor privilégio (`Storage Blob Data Contributor`, `Key Vault Secrets User`).
- Rede pública neste projeto (estudo); em produção real: Private Endpoints + Managed VNet do ADF.
- Criptografia em repouso e trânsito habilitada por padrão pela plataforma.

## Custos

| Medidor | Cobrança aproximada (2026) |
|---|---|
| Pipeline orchestration | ~US$ 1 / 1.000 execuções de atividade |
| Data movement (Copy Data) | ~US$ 0,25 / DIU-hora |
| Data Flow execution | ~US$ 0,27–0,34 / vCore-hora (mínimo 8 vCores) |

**Maior risco de custo:** Data Flow Debug esquecido ligado (60 min de cluster ativo por padrão). Estimativa de uma execução completa do pipeline mestre: **≈ US$ 0,62**, ~90% concentrado nos Data Flows.

## Consumo com Synapse Serverless SQL

Camada de consumo opcional sobre `gold/kpi_entregas/`, sem custo fixo (paga por TB escaneado):

```sql
CREATE EXTERNAL DATA SOURCE ds_gold
WITH (LOCATION = 'https://<storage>.dfs.core.windows.net/gold');

CREATE VIEW gold.kpi_entregas AS
SELECT * FROM OPENROWSET(
    BULK 'kpi_entregas/*.parquet',
    DATA_SOURCE = 'ds_gold',
    FORMAT = 'PARQUET'
) AS resultado;
```

Conecta diretamente ao Power BI (DirectQuery ou import) sem mover dados.

## Troubleshooting

| Erro | Causa provável | Solução |
|---|---|---|
| `Storage account not found` | Managed Identity sem role assignment | Confirmar `azurerm_role_assignment` no Terraform |
| `Login failed for user` | Connection string mal configurada no Key Vault | Revisar segredo e método de autenticação do Linked Service |
| `Forbidden` na API de clima | Rate limit da Open-Meteo | Usar `Sequential` no ForEach |
| Data Flow travado em "Queued" | Cold start do cluster | Aguardar alguns minutos |
| Storage Event Trigger não dispara | Event Grid não habilitado | Habilitar quando solicitado pelo Studio |
| Deploy falha no GitHub Actions | Service Principal sem permissão | Confirmar role `Contributor` em `AZURE_CREDENTIALS` |

## ADF vs. Databricks

| Critério | ADF | Databricks |
|---|---|---|
| Movimentação de dados heterogêneos | Muito forte (90+ conectores) | Requer código |
| Transformações simples (join/filter/agg) | Forte, visual, sem código | Requer PySpark |
| Regras de negócio complexas / ML | Limitado | Muito forte |
| Governança em nível de coluna | Inexistente nativamente | Unity Catalog |
| Custo para cargas pequenas | Mais barato | Cluster mínimo mais caro |

Em produção, é comum usar os dois juntos: ADF orquestra e move dados; Databricks concentra transformações complexas e ML.

## Referências

- [Documentação oficial do Azure Data Factory](https://learn.microsoft.com/azure/data-factory)
- [CI/CD com ADF](https://learn.microsoft.com/azure/data-factory/continuous-integration-delivery)
- [Pacote azure-data-factory-utilities](https://www.npmjs.com/package/@microsoft/azure-data-factory-utilities)
- [Calculadora de preços Azure](https://azure.microsoft.com/pricing/calculator)
- [API Open-Meteo](https://open-meteo.com)

---

*Documento gerado a partir da apostila "Azure Data Factory na Prática — Edição Engenheiro" (Agosto de 2026).*
