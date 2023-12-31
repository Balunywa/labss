RG="PAN-RG"
Location="eastus2"
hubname="Hub"

#Accept PAN license
az vm image terms accept --urn paloaltonetworks:vmseries-flex:byol:latest

#VNET
az group create --name PAN-RG --location $Location
az network vnet create --resource-group $RG --name $hubname --location $Location --address-prefixes 10.0.0.0/16 --subnet-name web --subnet-prefix 10.0.10.0/24
az network vnet subnet create --address-prefix 10.0.1.0/24 --name Untrust --resource-group $RG --vnet-name $hubname
az network vnet subnet create --address-prefix 10.0.2.0/24 --name Trust --resource-group $RG --vnet-name $hubname
az network vnet subnet create --address-prefix 10.0.3.0/24 --name PAN-Mgmt --resource-group $RG --vnet-name $hubname

#NSG
az network nsg create --resource-group $RG --name PAN-NSG --location $Location
az network nsg rule create --resource-group $RG --nsg-name PAN-NSG --name HTTPS --access Allow --protocol "TCP" --direction Inbound --priority 300 --source-address-prefix "*" --source-port-range "*" --destination-address-prefix "*" --destination-port-range "443"
az network nsg rule create --resource-group $RG --nsg-name PAN-NSG --name HTTP --access Allow --protocol "TCP" --direction Inbound --priority 400 --source-address-prefix "*" --source-port-range "*" --destination-address-prefix "*" --destination-port-range "80"

# Create Palo Alto firewalls in the hub VNET
az network public-ip create --name PAN1MgmtIP --resource-group $RG --idle-timeout 30 --sku Standard
az network public-ip create --name PAN1-Unrust-PublicIP --resource-group $RG --idle-timeout 30 --sku Standard
az network nic create --name PAN1MgmtInterface --resource-group $RG --subnet PAN-Mgmt --vnet-name $hubname --public-ip-address PAN1MgmtIP --private-ip-address 10.0.3.4 --network-security-group PAN-NSG
az network nic create --name PAN1UntrustInterface --resource-group $RG --subnet Untrust --vnet-name $hubname --private-ip-address 10.0.1.4 --ip-forwarding true --public-ip-address PAN1-Unrust-PublicIP --network-security-group PAN-NSG
az network nic create --name PAN1TrustInterface --resource-group $RG --subnet Trust --vnet-name $hubname --private-ip-address 10.0.2.4 --ip-forwarding true 
az vm create --resource-group $RG --location $Location --name PAN1 --size Standard_D8a_v4 --nics PAN1MgmtInterface PAN1UntrustInterface PAN1TrustInterface  --image paloaltonetworks:vmseries-flex:byol:latest --admin-username azureuser --admin-password Msft123Msft123 

az network public-ip create --name PAN2MgmtIP --resource-group $RG --idle-timeout 30 --sku Standard
az network public-ip create --name PAN2-Unrust-PublicIP --resource-group $RG --idle-timeout 30 --sku Standard
az network nic create --name PAN2MgmtInterface --resource-group $RG --subnet PAN-Mgmt --vnet-name $hubname --public-ip-address PAN2MgmtIP --private-ip-address 10.0.3.5 --network-security-group PAN-NSG
az network nic create --name PAN2UntrustInterface --resource-group $RG --subnet Untrust --vnet-name $hubname --private-ip-address 10.0.1.5 --ip-forwarding true --public-ip-address PAN2-Unrust-PublicIP --network-security-group PAN-NSG
az network nic create --name PAN2TrustInterface --resource-group $RG --subnet Trust --vnet-name $hubname --private-ip-address 10.0.2.5 --ip-forwarding true 
az vm create --resource-group $RG --location $Location --name PAN2 --size Standard_D8a_v4 --nics PAN2MgmtInterface PAN2UntrustInterface PAN2TrustInterface  --image paloaltonetworks:vmseries-flex:byol:latest --admin-username azureuser --admin-password Msft123Msft123 

# Create web VMs in the Hub
az network nic create --resource-group $RG -n Web1VMnic --location $Location --subnet web --private-ip-address 10.0.10.4 --vnet-name $hubname --ip-forwarding true
az vm create -n web1 --resource-group $RG --image Ubuntu2204 --admin-username azureuser --admin-password Msft123Msft123 --nics Web1VMnic --size Standard_D8a_v4
az vm extension set --publisher Microsoft.Azure.Extensions --version 2.0 --name CustomScript --vm-name web1 --resource-group $RG --settings '{"commandToExecute":"sudo apt-get -y update && sudo apt-get -y install nginx && sudo apt update"}'
az network nic create --resource-group $RG -n Web2VMnic --location $Location --subnet web --private-ip-address 10.0.10.5 --vnet-name $hubname --ip-forwarding true
az vm create -n web2 --resource-group $RG --image Ubuntu2204 --admin-username azureuser --admin-password Msft123Msft123 --nics Web2VMnic --size Standard_D8a_v4
az vm extension set --publisher Microsoft.Azure.Extensions --version 2.0 --name CustomScript --vm-name web2 --resource-group $RG --settings '{"commandToExecute":"sudo apt-get -y update && sudo apt-get -y install nginx && sudo apt update"}'

#ILB for inbound web
az network lb create --resource-group $RG --name ILB-Web-In --sku Standard --vnet-name Hub --subnet Trust --backend-pool-name myBackEndPool --frontend-ip-name myFrontEnd --private-ip-address 10.0.2.200
az network lb probe create --resource-group $RG --lb-name ILB-Web-In --name myHealthProbe --protocol tcp --port 80
az network lb rule create --resource-group $RG --lb-name ILB-Web-In --name myHTTPRule --protocol All --frontend-port 0 --backend-port 0 --frontend-ip-name myFrontEnd --backend-pool-name myBackEndPool --probe-name myHealthProbe --idle-timeout 15 --enable-tcp-reset true
az network nic ip-config address-pool add --address-pool myBackendPool --ip-config-name ipconfig1 --nic-name Web1VMnic --resource-group $RG --lb-name ILB-Web-In
az network nic ip-config address-pool add --address-pool myBackendPool --ip-config-name ipconfig1 --nic-name Web2VMnic --resource-group $RG --lb-name ILB-Web-In

#ILB for outbound
az network lb create --resource-group $RG --name ILB-Out --sku Standard --vnet-name Hub --subnet Trust --backend-pool-name Trust-BE --frontend-ip-name ILB-Out --private-ip-address 10.0.2.100
az network lb probe create --resource-group $RG --lb-name ILB-Out --name ILB-Out --protocol tcp --port 80
az network lb rule create --resource-group $RG --lb-name ILB-Out --name All --protocol All --frontend-port 0 --backend-port 0 --frontend-ip-name ILB-Out --backend-pool-name Trust-BE --probe-name ILB-Out --idle-timeout 15 --enable-tcp-reset true
az network nic ip-config address-pool add --address-pool Trust-BE --ip-config-name ipconfig1 --nic-name PAN1TrustInterface --resource-group $RG --lb-name ILB-Out

#Default route for web VMs pointing to outboud ILB
az network route-table create --name web-rt --resource-group $RG
az network route-table route create --name default --resource-group $RG --route-table-name web-rt --address-prefix "0.0.0.0/0" --next-hop-type VirtualAppliance --next-hop-ip-address 10.0.2.100
az network vnet subnet update --name web --vnet-name $hubname --resource-group $RG --route-table web-rt

#PLB
az network public-ip create --resource-group $RG --name PLB-PIP1 --sku Standard --zone 1
az network lb create --resource-group $RG --name PLB1 --sku Standard --public-ip-address PLB-PIP1 --frontend-ip-name PAN-Untrust-FE --backend-pool-name PAN-Untrust
az network lb probe create --resource-group $RG --lb-name PLB1 --name myHealthProbe --protocol tcp --port 80
az network lb rule create --resource-group $RG --lb-name PLB1 --name myHTTPRule --protocol tcp --frontend-port 80 --backend-port 80 --frontend-ip-name PAN-Untrust-FE --backend-pool-name PAN-Untrust --probe-name myHealthProbe --disable-outbound-snat true --idle-timeout 15 --enable-tcp-reset true --enable-floating-ip true
az network nic ip-config address-pool add --address-pool PAN-Untrust --ip-config-name ipconfig1 --nic-name PAN1UntrustInterface --resource-group $RG --lb-name PLB1
az network nic ip-config address-pool add --address-pool PAN-Untrust --ip-config-name ipconfig1 --nic-name PAN2UntrustInterface --resource-group $RG --lb-name PLB1

#Document public IP of PAN Mgmt interfaces
az network public-ip show --resource-group $RG --name PAN1MgmtIP --query [ipAddress] --output tsv
az network public-ip show --resource-group $RG --name PAN2MgmtIP --query [ipAddress] --output tsv
