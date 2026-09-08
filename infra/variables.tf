variable "prefixo" {
  description = "Prefixo usado em todos os recursos"
  type        = string
  default     = "rotacerta"
}

variable "ambiente" {
  description = "Ambiente de deploy (dev, test, prd)"
  type        = string
  default     = "dev"
}

variable "regiao" {
  description = "Regiao do Azure"
  type        = string
  default     = "westus2"
}

variable "sql_regiao" {
  description = "Regiao do Azure SQL Server (separada de var.regiao devido a restricao de provisionamento da assinatura em westus2/eastus). centralus tem o mesmo tier de preco de westus2, sem custo adicional."
  type        = string
  default     = "centralus"
}

variable "sql_admin_login" {
  description = "Login administrador do Azure SQL"
  type        = string
  default     = "rotacertaadmin"
}

variable "sql_admin_password" {
  description = "Senha do administrador do Azure SQL"
  type        = string
  sensitive   = true
}