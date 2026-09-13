output "resource_group_name" {
  value = azurerm_resource_group.kafka_spark.name
}

output "storage_account_name" {
  value = azurerm_storage_account.data_lake.name
}

output "cosmos_account_name" {
  value = azurerm_cosmosdb_account.cosmos.name
}
