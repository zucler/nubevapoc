#!/bin/bash

# trap exit commands to force them to run cleanup first
trap cleanup_artefacts SIGINT


#set arguement equal to resource group
NAME=
REGION=
PASSWORD=G0Nub3va20[]
DELETE=false

TEMPLATE_URL=https://raw.githubusercontent.com/ejfree/nubevapoc/master
TEMPLATE=azuretemplatev3.json

# Display the help message for the script
help () {
    echo ""
    echo "Nubeva Proof-of-Concept (POC) enviroment launching script"
    echo "---------"
    echo "| USAGE |"
    echo "---------"
    echo "CREATE: ./nubeva-poc-install -n nubevapoc -r westus -p NubevaCustomPass!"
    echo "DELETE: ./nubeva-poc-install -n nubevapoc -r westus -d"
    echo ""
    echo "-------------"
    echo "| ARGUMENTS |"
    echo "-------------"
    echo "-n|--name <name>"
    echo "    REQUIRED"
    echo "    The name of the POC resource group to create/delete"
    echo "-r|--region <region>"
    echo "    CONDITIONAL (Required for create only)"
    echo "    The region to use for the POC resource group"
    echo "-d|--delete"
    echo "    Flag to schedule a delete of a POC environment, if not specified goes to"
    echo "    create by default"
    echo "-p|--password <password>"
    echo "    Manually override the environment password, default is '$PASSWORD'"
    echo "-h|--help"
    echo "    Display this help message"
    echo ""
}

# Delete a resource group with a given name, to run pass in a -d|--delete flag
delete () {
    read -p "Are you sure you would like to delete resource group '$NAME'? [y/n]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]
    then
        echo ""
        echo "Running: 'az group delete --name $NAME'"
        echo ""
        az group delete --name $NAME
    fi
}

# Create a resource group with a give name in a given region (-n|--name, -r|--region)
create () {
    #create resource group
    echo Creating Resoure Group
    az group create --name $NAME --location $REGION

    #deploy azure template
    # Use local template to deploy
    echo Deploying Azure Template
    az group deployment create -g $NAME --template-uri $TEMPLATE_URL/$TEMPLATE


    #create 4 Vms
    echo Creating Source, Dest, and Bastion VMs and continuing.....
    az vm create --name source --resource-group $NAME --image UbuntuLTS  --admin-username nubeva  --admin-password $PASSWORD  --authentication-type password  --no-wait --nics sourceVNIC
    az vm create --name dest --resource-group $NAME --image UbuntuLTS  --admin-username nubeva  --admin-password $PASSWORD  --authentication-type password  --no-wait --nics destVNIC
    az vm create --name bastion --resource-group $NAME --image UbuntuLTS  --admin-username nubeva  --admin-password $PASSWORD  --authentication-type password  --no-wait --nics bastionVNIC

    echo Creating Peer VM and waiting.....
    az vm create --name peer --resource-group $NAME --image UbuntuLTS  --admin-username nubeva  --admin-password $PASSWORD  --authentication-type password --nics  peer-outsideVNIC peer-insideVNIC
    az vm create --name windows --resource-group $NAME --image win2016datacenter  --admin-username nubeva  --admin-password $PASSWORD --subnet bastion --vnet-name nubevapoc-vnet


    #Update route table, IP forwarding, and enable outbound NAT w/masquerade on Peer VM
    echo Modifying Peer Routes, Forwarding, and NAT.
    az vm extension set --resource-group $NAME --vm-name peer --name customScript --publisher Microsoft.Azure.Extensions --settings '{"fileUris": ["https://raw.githubusercontent.com/ejfree/nubevapoc/master/routemod.sh"],"commandToExecute": "./routemod.sh"}'
    az vm extension set --resource-group $NAME --vm-name bastion --name customScript --publisher Microsoft.Azure.Extensions --settings '{"fileUris": ["https://raw.githubusercontent.com/ejfree/nubevapoc/master/add_vxlan.sh"],"commandToExecute": "./add_vxlan.sh"}'
    #Below doesnt work yet. 
    #az vm extension set --resource-group $NAME --vm-name windows --name customScript --publisher Microsoft.Azure.Extensions --settings '{"fileUris": ["https://raw.githubusercontent.com/ejfree/nubevapoc/master/Post-Install.ps1"],"commandToExecute": "Post-Install.ps1"}'
}


# Argparsing
while [[ $# -gt 0 ]]
do
    key="$1"
    case $key in
        -d|--delete)
            DELETE=true
            shift
            ;;
        -h|--help)
            help
            exit 0
            ;;
        -n|--name)
            NAME=$2
            shift
            shift
            ;;
        -r|--region)
            REGION=$2
            shift
            shift
            ;;
        -p|--password)
            PASSWORD=$2
            shift
            shift
            ;;
        *)
            echo "Unknown argument '$key', skipping..."
            shift
            ;;
    esac
done

#echo "DELETE   = $DELETE"
#echo "REGION   = $REGION"
#echo "NAME     = $NAME"
#echo "PASSWORD = $PASSWORD"

if [ -z "$NAME" ]
then
    echo "Required argument resource group name is unset, please specify using '-n <name>'"
    exit 1
fi

if [ "$DELETE" = true ]
then
    delete
else
    if [ -z "$REGION" ]
    then
        echo "Required argument region is unset, please specify using '-r <region>'"
        exit 1
    fi
    create
fi

