# ==============================================================================
# Terraform & Providers
# ==============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# ==============================================================================
# Data Sources
# ==============================================================================

data "azurerm_client_config" "atual" {}

data "http" "meu_ip" {
  url = "https://api.ipify.org"
}

# ==============================================================================
# Locals
# ==============================================================================

locals {
  tags = {
    projeto        = "rotacerta-data-platform"
    ambiente       = var.ambiente
    gerenciado_por = "terraform"
  }
}

# ==============================================================================
# Resource Group
# ==============================================================================

resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefixo}-${var.ambiente}"
  location = var.regiao
  tags     = local.tags
}

# ==============================================================================
# Storage Account (ADLS Gen2)
# ==============================================================================

resource "azurerm_storage_account" "storage" {
  name                     = "st${var.prefixo}${var.ambiente}adf"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
  tags                     = local.tags
}

resource "azurerm_storage_container" "landing" {
  name                  = "landing"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "gold" {
  name                  = "gold"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

# ==============================================================================
# Azure SQL Database
# ==============================================================================
# NOTA: o SQL Server fica em uma regiao separada (var.sql_regiao, default
# "eastus2") porque esta assinatura tem provisionamento de Microsoft.Sql/servers
# bloqueado em westus2 (erro "ProvisioningDisabled" - restricao da assinatura,
# nao de quota). Todo o resto do projeto permanece em var.regiao (westus2).

resource "azurerm_mssql_server" "sql" {
  name                         = "sql-${var.prefixo}-${var.ambiente}-v3"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.sql_regiao
  version                      = "12.0"
  administrator_login          = var.sql_admin_login
  administrator_login_password = var.sql_admin_password
  tags                         = local.tags
}

resource "azurerm_mssql_database" "db" {
  name                        = "sqldb-${var.prefixo}"
  server_id                   = azurerm_mssql_server.sql.id
  sku_name                    = "GP_S_Gen5_1"
  auto_pause_delay_in_minutes = 60
  min_capacity                = 0.5
  tags                        = local.tags
}

resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "allow_meu_ip" {
  name             = "AllowMeuIP"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = chomp(data.http.meu_ip.response_body)
  end_ip_address   = chomp(data.http.meu_ip.response_body)
}

# ==============================================================================
# Key Vault
# ==============================================================================

resource "azurerm_key_vault" "kv" {
  name                = "kv-${var.prefixo}-${var.ambiente}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = data.azurerm_client_config.atual.tenant_id
  sku_name            = "standard"
  tags                = local.tags
}

resource "azurerm_key_vault_access_policy" "user" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.atual.tenant_id
  object_id          = data.azurerm_client_config.atual.object_id
  secret_permissions = ["Get", "List", "Set", "Delete", "Purge"]
}

resource "azurerm_key_vault_secret" "sql_connection_string" {
  name         = "sql-connection-string"
  key_vault_id = azurerm_key_vault.kv.id
  value        = "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.db.name};Persist Security Info=False;User ID=${var.sql_admin_login};Password=${var.sql_admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  depends_on   = [azurerm_key_vault_access_policy.user]
}

# ==============================================================================
# Data Factory
# ==============================================================================

resource "azurerm_data_factory" "adf" {
  name                = "adf-${var.prefixo}-${var.ambiente}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# ==============================================================================
# Access & Permissions
# ==============================================================================

resource "azurerm_role_assignment" "adf_storage_blob_contributor" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

resource "azurerm_key_vault_access_policy" "adf" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.atual.tenant_id
  object_id          = azurerm_data_factory.adf.identity[0].principal_id
  secret_permissions = ["Get", "List"]
}