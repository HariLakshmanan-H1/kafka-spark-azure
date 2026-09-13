terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.81.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = "67cc1675-8cc3-4f67-8b15-e47a056675f7"

  use_cli = true
  use_msi = false

  resource_provider_registrations = "none"
}


# ============================================================
# RESOURCE GROUP
# ============================================================

resource "azurerm_resource_group" "kafka_spark" {
  name     = "kafka-spark-rg"
  location = "polandcentral"
}


# ============================================================
# NETWORKING
# ============================================================

resource "azurerm_virtual_network" "kafka_vm" {
  name                = "kafka-vmVNET"
  location            = azurerm_resource_group.kafka_spark.location
  resource_group_name = azurerm_resource_group.kafka_spark.name

  address_space = [
    "10.0.0.0/16"
  ]
}


resource "azurerm_subnet" "kafka_vm" {
  name                 = "kafka-vmSubnet"
  resource_group_name  = azurerm_resource_group.kafka_spark.name
  virtual_network_name = azurerm_virtual_network.kafka_vm.name

  address_prefixes = [
    "10.0.0.0/24"
  ]
}


resource "azurerm_public_ip" "kafka_vm" {
  name                = "kafka-vmPublicIP"
  resource_group_name = azurerm_resource_group.kafka_spark.name
  location            = azurerm_resource_group.kafka_spark.location

  allocation_method = "Static"
  sku               = "Standard"
}


resource "azurerm_network_security_group" "kafka_vm" {
  name                = "kafka-vmNSG"
  location            = azurerm_resource_group.kafka_spark.location
  resource_group_name = azurerm_resource_group.kafka_spark.name

  security_rule {
    name      = "default-allow-ssh"
    priority  = 1000
    direction = "Inbound"
    access    = "Allow"
    protocol  = "Tcp"

    source_port_range      = "*"
    destination_port_range = "22"

    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}


resource "azurerm_network_interface" "kafka_vm" {
  name                = "kafka-vmVMNic"
  location            = azurerm_resource_group.kafka_spark.location
  resource_group_name = azurerm_resource_group.kafka_spark.name

  ip_configuration {
    name                          = "ipconfigkafka-vm"
    subnet_id                     = azurerm_subnet.kafka_vm.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.kafka_vm.id
  }
}


resource "azurerm_network_interface_security_group_association" "kafka_vm" {
  network_interface_id      = azurerm_network_interface.kafka_vm.id
  network_security_group_id = azurerm_network_security_group.kafka_vm.id
}


# ============================================================
# ADLS GEN2 STORAGE ACCOUNT
# ============================================================

resource "azurerm_storage_account" "data_lake" {
  name                = "kafkasparkdatalake"
  resource_group_name = azurerm_resource_group.kafka_spark.name
  location            = azurerm_resource_group.kafka_spark.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  is_hns_enabled = true

  allow_nested_items_to_be_public = false

  min_tls_version = "TLS1_2"
}


resource "azurerm_storage_data_lake_gen2_filesystem" "ecommerce" {
  name               = "ecommerce"
  storage_account_id = azurerm_storage_account.data_lake.id
}


resource "azurerm_storage_data_lake_gen2_path" "bronze" {
  path               = "bronze"
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.ecommerce.name
  storage_account_id = azurerm_storage_account.data_lake.id
  resource           = "directory"
}


resource "azurerm_storage_data_lake_gen2_path" "silver" {
  path               = "silver"
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.ecommerce.name
  storage_account_id = azurerm_storage_account.data_lake.id
  resource           = "directory"
}


resource "azurerm_storage_data_lake_gen2_path" "gold" {
  path               = "gold"
  filesystem_name    = azurerm_storage_data_lake_gen2_filesystem.ecommerce.name
  storage_account_id = azurerm_storage_account.data_lake.id
  resource           = "directory"
}


# ============================================================
# COSMOS DB
# ============================================================

resource "azurerm_cosmosdb_account" "cosmos" {
  name                = "kafkasparkcosmos"
  location            = azurerm_resource_group.kafka_spark.location
  resource_group_name = azurerm_resource_group.kafka_spark.name

  offer_type = "Standard"

  automatic_failover_enabled = true

  geo_location {
    location          = "polandcentral"
    failover_priority = 0
  }

  consistency_policy {
    consistency_level = "Session"
  }

  capabilities {
    name = "EnableServerless"
  }
}


# ============================================================
# KAFKA / SPARK VM
# ============================================================

resource "azurerm_linux_virtual_machine" "kafka_vm" {
  name                = "kafka-vm"
  resource_group_name = azurerm_resource_group.kafka_spark.name
  location            = azurerm_resource_group.kafka_spark.location

  size           = "Standard_B2s_v2"
  admin_username = "azureuser"

  network_interface_ids = [
    azurerm_network_interface.kafka_vm.id
  ]

  disable_password_authentication = true

  admin_ssh_key {
    username = "azureuser"

    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDYRMQRsI3xkH8S7zeaLd8XSdnqy1fdAIhWFC9h12mYEHVIYzMqpm5e59Sm2M//cH2PdADphw0YGaVPFnxkxJNw4Xc2jTPJXPMC+Y65HKWdNrxqx13fLUiB+4WEX/xxHdZxK3jJ8UldkYEcbGrsDWsdtRHH06AlvAx+uTCnONs5I2h3HrucphLVwfq6+7ZEJSQFwQqLnml6akmbJSxrkAm8M0hn2qJcMRKYl4lYZnW0jL0eaIWmLK9nHE0XR1Fub56ydq1Y/XiDOMkZW2HFJFpU+1GVdKtNkEkuRCKP5Ir5N3Bv5tNKJBkPgmHlNA2HYjaomD79f1mCKR9auuY5ys91"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}


# ============================================================
# STORAGE RBAC
# ============================================================

resource "azurerm_role_assignment" "vm_storage_blob_contributor" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"

  principal_id = azurerm_linux_virtual_machine.kafka_vm.identity[0].principal_id
}


# ============================================================
# COSMOS DB RBAC
# ============================================================

resource "azurerm_cosmosdb_sql_role_assignment" "vm_cosmos_contributor" {
  resource_group_name = azurerm_resource_group.kafka_spark.name
  account_name        = azurerm_cosmosdb_account.cosmos.name

  principal_id = azurerm_linux_virtual_machine.kafka_vm.identity[0].principal_id

  role_definition_id = "${azurerm_cosmosdb_account.cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"

  scope = azurerm_cosmosdb_account.cosmos.id
}


# ============================================================
# LOG ANALYTICS
# ============================================================

resource "azurerm_log_analytics_workspace" "kafka_spark_logs" {
  name                = "kafka-spark-logs"
  location            = azurerm_resource_group.kafka_spark.location
  resource_group_name = azurerm_resource_group.kafka_spark.name

  sku               = "PerGB2018"
  retention_in_days = 30

  local_authentication_enabled = true
}


# ============================================================
# AZURE MONITOR AGENT
# ============================================================

resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  name               = "AzureMonitorLinuxAgent"
  virtual_machine_id = azurerm_linux_virtual_machine.kafka_vm.id

  publisher = "Microsoft.Azure.Monitor"
  type      = "AzureMonitorLinuxAgent"

  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
}


# ============================================================
# DATA COLLECTION RULE
# ============================================================

resource "azurerm_monitor_data_collection_rule" "kafka_vm" {
  name                = "msvmi-polandcentral-kafka-vm"
  resource_group_name = azurerm_resource_group.kafka_spark.name
  location            = azurerm_resource_group.kafka_spark.location

  destinations {
    monitor_account {
      name = "MonitoringAccountDestination"

      monitor_account_id = "/subscriptions/67cc1675-8cc3-4f67-8b15-e47a056675f7/resourcegroups/defaultresourcegroup-plc/providers/microsoft.monitor/accounts/defaultazuremonitorworkspace-plc"
    }
  }

  data_flow {
    streams = [
      "Microsoft-OtelPerfMetrics"
    ]

    destinations = [
      "MonitoringAccountDestination"
    ]
  }
}

resource "azurerm_role_assignment" "vm_monitoring_contributor" {
  scope                = "/subscriptions/67cc1675-8cc3-4f67-8b15-e47a056675f7/resourceGroups/defaultresourcegroup-plc/providers/Microsoft.Monitor/accounts/defaultazuremonitorworkspace-plc"
  role_definition_name = "Monitoring Contributor"
  principal_id         = azurerm_linux_virtual_machine.kafka_vm.identity[0].principal_id
}

resource "azurerm_monitor_data_collection_rule_association" "kafka_vm" {
  name                    = "kafka-vm-dcr-association"
  target_resource_id      = azurerm_linux_virtual_machine.kafka_vm.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.kafka_vm.id
}

resource "azurerm_monitor_metric_alert" "kafka_vm_high_cpu" {
  name                = "kafka-vm-high-cpu"
  resource_group_name = azurerm_resource_group.kafka_spark.name
  scopes              = [azurerm_linux_virtual_machine.kafka_vm.id]
  description         = "Alert when Kafka VM average CPU exceeds 80 percent"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }
}
