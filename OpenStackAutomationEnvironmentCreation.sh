#!/bin/bash

# Starting the Script

source ~/admin-rc

export OS_COMPUTE_API_VERSION=2.55

echo "Creation of OpenStack Environment Started"
echo

openstack network set --description "Shared external network for CloudLearn" --tag course:test provider-datacentre

echo "Creating new OpenStack domain named CloudLearnDomain"
openstack domain create --description "Domain for CloudLearn" CloudLearnDomain 

echo "Creating new project named CloudLearn"
openstack project create --domain CloudLearnDomain --description "Project for CloudLearn" CloudLearn --tag course:test

echo "Creating Student group and Instructor group"
openstack group create --domain CloudLearnDomain --description "Group for Students" StudentGroup 
openstack group create --domain CloudLearnDomain --description "Group for Instructors" InstructorGroup 

# Wait for groups to exist
for i in {1..10}; do
    openstack group show --domain CloudLearnDomain StudentGroup && break
    echo "Waiting for Student Group to be available..."
    sleep 2
done

for i in {1..10}; do
    openstack group show --domain CloudLearnDomain InstructorGroup && break
    echo "Waiting for Instructor Group to be available..."
    sleep 2
done

# Creating users, projects and assigning roles based on CSV file
allinstructors=$(mktemp)
tail -n +2 Original_Popis_studenata.csv | while IFS=';' read -r ime prezime rola
do
    username="$ime.$prezime"

    echo "Adding user $ime $prezime to project"
    openstack user create --domain CloudLearnDomain --project CloudLearn --password Pa$$w0rd123 $ime.$prezime
    
    # Adding user to appropriate group
    if [ "$rola" == "instructor" ]; then
        projectname="$username-Instructor-Project"

        echo "Adding user to instructor group"
        openstack group add user --domain CloudLearnDomain InstructorGroup $username

        echo "Creating project for instructor"
        openstack project create --domain CloudLearnDomain --parent CloudLearn --description "Project for $ime $prezime" $projectname --tag course:test

        openstack role add --project $projectname --user $username admin

        echo "Creating a private network for instructor $username"
        openstack network create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --no-share \
        --description "Private network for $username" \
        --tag course:test \
        $username-private-network

        echo "Creating the subnet for the private network"
        openstack subnet create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --network $username-private-network \
        --subnet-range 192.168.0.0/24 \
        --description "Private subnet for $username" \
        --tag course:test \
        $username-private-subnet

        echo "Creating router for $username"
        openstack router create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --description "Router for $username" \
        $username-router \
        --tag course:test

        openstack router add subnet $username-router $username-private-subnet
        openstack router set --external-gateway provider-datacentre $username-router

        echo "Creating JumpHost security group for $username"
        
        openstack security group create \
        --project $projectname \
        --description "JumpHost security group for $username" \
        $username-jumphost-secgroup \
        --tag course:test

        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 22 --ingress --description "Allow SSH" $username-jumphost-secgroup

        
        echo "Creating WordPress security group for $username"
        
        openstack security group create \
        --project $projectname \
        --description "WordPress security group for $username" \
        $username-wordpress-secgroup \
        --tag course:test

        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 80 --ingress --description "Allow HTTP" $username-wordpress-secgroup
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 443 --ingress --description "Allow HTTPS" $username-wordpress-secgroup

        openstack role add --project $projectname --user $username admin

        echo "$username" >> $allinstructors
    
    elif [ "$rola" == "student" ]; then
        projectname="$username-Student-Project"

        echo "Adding user to student group"
        openstack group add user --domain CloudLearnDomain StudentGroup $username

        echo "Creating project for student"
        openstack project create --domain CloudLearnDomain --parent CloudLearn --description "Project for $ime $prezime" $projectname --tag course:test

        echo "Creating a private network for student $username"
        openstack network create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --no-share \
        --description "Private network for $username" \
        $username-private-network

        echo "Creating the subnet for the private network"
        openstack subnet create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --network $username-private-network \
        --subnet-range 192.168.0.0/24 \
        --description "Private subnet for $username" \
        $username-private-subnet

        echo "Creating router for $username"
        openstack router create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --description "Router for $username" \
        $username-router \
        --tag course:test
        openstack router add subnet $username-router $username-private-subnet
        openstack router set --external-gateway provider-datacentre $username-router


        echo "Creating JumpHost security group for $username"
        
        openstack security group create \
        --project $projectname \
        --description "JumpHost security group for $username" \
        $username-jumphost-secgroup \
        --tag course:test

        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 22 --ingress --description "Allow SSH" $username-jumphost-secgroup
        
        
        echo "Creating WordPress security group for $username"
        
        openstack security group create \
        --project $projectname \
        --description "WordPress security group for $username" \
        $username-wordpress-secgroup \
        --tag course:test
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 80 --ingress --description "Allow HTTP" $username-wordpress-secgroup
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 443 --ingress --description "Allow HTTPS" $username-wordpress-secgroup

        openstack role add --project $projectname --user $username admin
    fi
done

# Assigning all instructors as admins in all student projects
tail -n +2 Original_Popis_studenata.csv | while IFS=';' read -r ime prezime rola
do
    if [ "$rola" == "student" ]; then
        projectname="$ime.$prezime-Student-Project"
        while read -r instructor; do
            openstack role add --project $projectname --user $instructor admin
        done < $allinstructors
    fi
done

rm -f $allinstructors

# Configuring Image and Flavor

wget -q https://cloud-images.ubuntu.com/daily/server/jammy/current/jammy-server-cloudimg-amd64.img

openstack image create \
--file jammy-server-cloudimg-amd64.img \
--disk-format qcow2 \
--container-format bare \
--public \
--tag course:test \
Ubuntu-Server

openstack flavor create \
--ram 1024 \
--disk 16 \
--ephemeral 16 \
--vcpus 1 \
--public \
--description "Flavor for Ubuntu server instances" \
--project-domain CloudLearnDomain \
Ubuntu-Server-Flavor

# Creating instances and configuring

tail -n +2 Original_Popis_studenata.csv | while IFS=';' read -r ime prezime rola
do
    if [ "$rola" == "instructor" ]; then
    username="$ime.$prezime"
    projectname="$username-Instructor-Project"

    ssh-keygen -t rsa -b 2048 -f $username-JumpHost-key -N ""
    ssh-keygen -t rsa -b 2048 -f $username-WordPress-key -N ""

    openstack keypair create --user $username --public-key $username-JumpHost-key.pub $username-JumpHost-key
    openstack keypair create --user $username --public-key $username-WordPress-key.pub $username-WordPress-key

    cat $username-JumpHost-key.pub $username-WordPress-key.pub > $username-CombinedJumpHost-key.pub
    openstack keypair create --user $username --public-key $username-CombinedJumpHost-key.pub $username-CombinedJumpHost-key

    echo "Creating Instructor JumpHost instance"

        openstack server create \
        --project $projectname \
        --flavor Ubuntu-Server-Flavor \
        --image Ubuntu-Server \
        --nic net-id=$(openstack network show -f value -c id $username-private-network) \
        --security-group $username-jumphost-secgroup \
        --key-name $username-CombinedJumpHost-key \
        $username-jumphost

    echo "Creating WordPress instances for $username"

    for i in {1..4}; do 
        openstack server create \
            --project $projectname \
            --flavor Ubuntu-Server-Flavor \
            --image Ubuntu-Server \
            --nic net-id=$(openstack network show -f value -c id $username-private-network) \
            --security-group $username-wordpress-secgroup \
            --key-name $username-WordPress-key \
            --user-data cloud-init-wordpress.yaml \
            $username-wordpress-$i
    done

    openstack loadbalancer create --name $username-lb --vip-subnet-id $username-private-subnet --project $projectname

    openstack loadbalancer listener create --name $username-http-listener --protocol HTTP --protocol-port 80 $username-lb
    openstack loadbalancer pool create --name $username-http-pool --lb $username-lb --listener $username-http-listener --protocol HTTP --lb-algorithm ROUND_ROBIN

    openstack loadbalancer listener create --name $username-https-listener --protocol HTTPS --protocol-port 443 $username-lb
    openstack loadbalancer pool create --name $username-https-pool --lb $username-lb --listener $username-https-listener --protocol HTTPS --lb-algorithm ROUND_ROBIN

    openstack loadbalancer listener create --name $username-ssh-listener --protocol TCP --protocol-port 22 $username-lb
    openstack loadbalancer pool create --name $username-ssh-pool --lb $username-lb --listener $username-ssh-listener --protocol TCP --lb-algorithm ROUND_ROBIN

    # Get JumpHost private IP
    JUMPHOST_IP=$(openstack server show -f value -c addresses $username-jumphost | awk -F '=' '{print $2}')

    openstack loadbalancer member create --subnet-id $username-private-subnet --address $JUMPHOST_IP --protocol-port 22 $username-ssh-pool

    for i in {1..4}; do
        WP_IP=$(openstack server show -f value -c addresses $username-wordpress-$i | awk -F '=' '{print $2}')
        openstack loadbalancer member create --subnet-id $username-private-subnet --address $WP_IP --protocol-port 80 $username-http-pool
    done

    for i in {1..4}; do
        WP_IP=$(openstack server show -f value -c addresses $username-wordpress-$i | awk -F '=' '{print $2}')
        openstack loadbalancer member create --subnet-id $username-private-subnet --address $WP_IP --protocol-port 443 $username-https-pool
    done

    FLOATING_IP=$(openstack floating ip create -f value -c floating_ip_address provider-datacentre)
    LB_VIP_PORT_ID=$(openstack loadbalancer show $username-lb -f value -c vip_port_id)
    openstack floating ip set --port $LB_VIP_PORT_ID $FLOATING_IP

    elif [ "$rola" == "student" ]; then
    username="$ime.$prezime"
    projectname="$username-Student-Project"

    ssh-keygen -t rsa -b 2048 -f $username-JumpHost-key -N ""
    ssh-keygen -t rsa -b 2048 -f $username-WordPress-key -N ""

    openstack keypair create --user $username --public-key $username-JumpHost-key.pub $username-JumpHost-key
    openstack keypair create --user $username --public-key $username-WordPress-key.pub $username-WordPress-key

    cat $username-JumpHost-key.pub $username-WordPress-key.pub > $username-CombinedJumpHost-key.pub
    openstack keypair create --user $username --public-key $username-CombinedJumpHost-key.pub $username-CombinedJumpHost-key

    echo "Creating student JumpHost instance"

        openstack server create \
        --project $projectname \
        --flavor Ubuntu-Server-Flavor \
        --image Ubuntu-Server \
        --nic net-id=$(openstack network show -f value -c id $username-private-network) \
        --security-group $username-jumphost-secgroup \
        --key-name $username-CombinedJumpHost-key \
        $username-jumphost

    echo "Creating WordPress instances for $username"

    for i in {1..4}; do 
        openstack server create \
            --project $projectname \
            --flavor Ubuntu-Server-Flavor \
            --image Ubuntu-Server \
            --nic net-id=$(openstack network show -f value -c id $username-private-network) \
            --security-group $username-wordpress-secgroup \
            --key-name $username-WordPress-key \
            --user-data cloud-init-wordpress.yaml \
            $username-wordpress-$i
    done

        # Create load balancer for student
    openstack loadbalancer create --name $username-lb --vip-subnet-id $username-private-subnet --project $projectname

    # Create listeners and pools
    openstack loadbalancer listener create --name $username-http-listener --protocol HTTP --protocol-port 80 $username-lb
    openstack loadbalancer pool create --name $username-http-pool --lb $username-lb --listener $username-http-listener --protocol HTTP --lb-algorithm ROUND_ROBIN

    openstack loadbalancer listener create --name $username-https-listener --protocol HTTPS --protocol-port 443 $username-lb
    openstack loadbalancer pool create --name $username-https-pool --lb $username-lb --listener $username-https-listener --protocol HTTPS --lb-algorithm ROUND_ROBIN

    openstack loadbalancer listener create --name $username-ssh-listener --protocol TCP --protocol-port 22 $username-lb
    openstack loadbalancer pool create --name $username-ssh-pool --lb $username-lb --listener $username-ssh-listener --protocol TCP --lb-algorithm ROUND_ROBIN

    # Add JumpHost to SSH pool
    JUMPHOST_IP=$(openstack server show -f value -c addresses $username-jumphost | awk -F '=' '{print $2}')
    openstack loadbalancer member create --subnet-id $username-private-subnet --address $JUMPHOST_IP --protocol-port 22 $username-ssh-pool

    # Add WordPress VMs to HTTP and HTTPS pools
    for i in {1..4}; do
        WP_IP=$(openstack server show -f value -c addresses $username-wordpress-$i | awk -F '=' '{print $2}')
        openstack loadbalancer member create --subnet-id $username-private-subnet --address $WP_IP --protocol-port 80 $username-http-pool
        openstack loadbalancer member create --subnet-id $username-private-subnet --address $WP_IP --protocol-port 443 $username-https-pool
    done

    # Allocate and associate a floating IP to the student's load balancer VIP
    FLOATING_IP=$(openstack floating ip create -f value -c floating_ip_address provider-datacentre)
    LB_VIP_PORT_ID=$(openstack loadbalancer show $username-lb -f value -c vip_port_id)
    openstack floating ip set --port $LB_VIP_PORT_ID $FLOATING_IP
    fi
done
