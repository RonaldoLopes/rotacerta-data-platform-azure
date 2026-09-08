output "storage_account_name" {
  value = azurerm_storage_account.storage.name
}

output "data_factory_name" {
  value = azurerm_data_factory.adf.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}