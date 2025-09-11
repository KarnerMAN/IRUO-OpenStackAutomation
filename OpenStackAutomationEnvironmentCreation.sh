#!/bin/bash

# Starting the Script

source admin-rc

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


# Configuring Image and Flavor

echo "Creating Ubuntu-Server image"

wget -q https://cloud-images.ubuntu.com/daily/server/jammy/current/jammy-server-cloudimg-amd64.img

openstack image create \
--file jammy-server-cloudimg-amd64.img \
--disk-format qcow2 \
--container-format bare \
--public \
--tag course:test \
Ubuntu-Server

echo "Creating flavor for Ubuntu server instances"

openstack flavor create \
--ram 1024 \
--disk 16 \
--ephemeral 16 \
--vcpus 1 \
--public \
--project-domain CloudLearnDomain \
Ubuntu-Server-Flavor


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
while IFS=';' read -r ime prezime rola
do

    ime=$(echo "$ime" | xargs | tr -d '\r')
    prezime=$(echo "$prezime" | xargs | tr -d '\r')
    rola=$(echo "$rola" | xargs | tr -d '\r')

    username="$ime.$prezime"

    echo "Adding user $ime $prezime to project"
    openstack user create --domain CloudLearnDomain --project CloudLearn --password 'Pa$$w0rd123' $username

    # Adding user to appropriate group
    if [[ "$rola" == "instruktor" ]]; then
        projectname="$username-Instructor-Project"

        echo "Adding user to instructor group"
        openstack group add user --user-domain CloudLearnDomain --group-domain CloudLearnDomain InstructorGroup $username

        echo "Creating project for instructor"
        openstack project create --domain CloudLearnDomain --parent CloudLearn --description "Project for $ime $prezime" $projectname --tag course:test

        openstack role add --group-domain CloudLearnDomain --project $projectname --project-domain CloudLearnDomain --user $username --user-domain CloudLearnDomain admin

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

        echo "$username" >> $allinstructors

    elif [[ "$rola" == "student" ]]; then
        projectname="$username-Student-Project"

        echo "Adding user to student group"
        openstack group add user --user-domain CloudLearnDomain --group-domain CloudLearnDomain StudentGroup $username

        echo "Creating project for student"
        openstack project create --domain CloudLearnDomain --parent CloudLearn --description "Project for $ime $prezime" $projectname --tag course:test

        openstack role add --group-domain CloudLearnDomain --project $projectname --project-domain CloudLearnDomain --user $username --user-domain CloudLearnDomain admin

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

    fi
done < <(tail -n +2 Original_Popis_studenata.csv)

# Assigning all instructors as admins in all student projects

echo "Giving instructors admin role in all student projects"
while IFS=';' read -r ime prezime rola
do

    ime=$(echo "$ime" | xargs | tr -d '\r')
    prezime=$(echo "$prezime" | xargs | tr -d '\r')
    rola=$(echo "$rola" | xargs | tr -d '\r')

    if [[ "$rola" == "student" ]]; then
        projectname="$ime.$prezime-Student-Project"
        while read -r instructor; do
            openstack role add --project $projectname --user $instructor --user-domain CloudLearnDomain admin
        done < $allinstructors
    fi
done < <(tail -n +2 Original_Popis_studenata.csv)

rm -f $allinstructors
# Creating instances and configuring

while IFS=';' read -r ime prezime rola
do

    ime=$(echo "$ime" | xargs | tr -d '\r')
    prezime=$(echo "$prezime" | xargs | tr -d '\r')
    rola=$(echo "$rola" | xargs | tr -d '\r')

    if [[ "$rola" == "instruktor" ]]; then
        username="$ime.$prezime"
        projectname="$username-Instructor-Project"

        # SSH key logic

        # Make names safe

        safe_base=$(echo "$username" | sed 's/[^A-Za-z0-9_-]/_/g')

        # Safe keypair names
        safe_jump_key="${safe_base}-JumpHost-key"
        safe_wp_key="${safe_base}-WordPress-key"
        safe_combined_key="${safe_base}-CombinedJumpHost-key"

        # Generate SSH keys (safe filenames)
        ssh-keygen -t rsa -b 2048 -f "$safe_jump_key" -N ""
        ssh-keygen -t rsa -b 2048 -f "$safe_wp_key" -N ""


        # Create OpenStack keypairs with safe names
        openstack keypair create --public-key "$safe_jump_key.pub" "$safe_jump_key"
        openstack keypair create --public-key "$safe_wp_key.pub" "$safe_wp_key"

        # Combine public keys and create combined keypair
        cat "$safe_jump_key.pub" "$safe_wp_key.pub" > "$safe_combined_key.pub"
        openstack keypair create --public-key "$safe_combined_key.pub" "$safe_combined_key"

        echo "Creating Instructor JumpHost instance"

            openstack server create \
            --flavor Ubuntu-Server-Flavor \
            --image Ubuntu-Server \
            --nic net-id=$(openstack network show -f value -c id $username-private-network) \
            --security-group $username-jumphost-secgroup \
            --key-name $safe_combined_key \
            $username-jumphost

        echo "Creating WordPress instances for $username"

        for i in {1..4}; do
            openstack server create \
                --flavor Ubuntu-Server-Flavor \
                --image Ubuntu-Server \
                --nic net-id=$(openstack network show -f value -c id $username-private-network) \
                --security-group $username-wordpress-secgroup \
                --key-name $safe_wp_key \
                --user-data cloud-init-wordpress.yaml \
                $username-wordpress-$i

        done

        SUBNET_ID=$(openstack subnet show -f value -c id $username-private-subnet)

        echo "Creating load balancer for $username in project $projectname"

        # Use private subnet for VIP (students connect here, external access via floating IP)
        openstack loadbalancer create \
            --name $username-lb \
            --vip-subnet-id $SUBNET_ID \
            --project $projectname

        # Wait for LB to become ACTIVE
        while true; do
            STATUS=$(openstack loadbalancer show $username-lb -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for load balancer $username-lb to become ACTIVE..."
            sleep 10
        done


        # Create HTTP listener and pool
        openstack loadbalancer listener create --name $username-http-listener --protocol HTTP --protocol-port 80 $username-lb
        while true; do
            STATUS=$(openstack loadbalancer listener show $username-http-listener -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for listener $username-http-listener to become ACTIVE..."
            sleep 10
        done
        openstack loadbalancer pool create --name $username-http-pool --lb $username-lb --listener $username-http-listener --protocol HTTP --lb-algorithm ROUND_ROBIN

        # Create HTTPS listener and pool
        openstack loadbalancer listener create --name $username-https-listener --protocol HTTPS --protocol-port 443 $username-lb
        while true; do
            STATUS=$(openstack loadbalancer listener show $username-https-listener -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for listener $username-https-listener to become ACTIVE..."
            sleep 10
        done
        openstack loadbalancer pool create --name $username-https-pool --lb $username-lb --listener $username-https-listener --protocol HTTPS --lb-algorithm ROUND_ROBIN

        # Create SSH listener and pool
        openstack loadbalancer listener create --name $username-ssh-listener --protocol TCP --protocol-port 22 $username-lb
        while true; do
            STATUS=$(openstack loadbalancer listener show $username-ssh-listener -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for listener $username-ssh-listener to become ACTIVE..."
            sleep 10
        done
        openstack loadbalancer pool create --name $username-ssh-pool --lb $username-lb --listener $username-ssh-listener --protocol TCP --lb-algorithm ROUND_ROBIN

        # Add JumpHost and WordPress instances as pool members (from student's private subnet)
        SUBNET_ID=$(openstack subnet show -f value -c id $username-private-subnet)
        # JumpHost
        JUMPHOST_IP=$(openstack server show -f value -c addresses $username-jumphost | awk -F '=' '{print $2}')
        openstack loadbalancer member create --subnet-id $SUBNET_ID --address $JUMPHOST_IP --protocol-port 22 $username-ssh-pool
        # WordPress
        for i in {1..4}; do
            WP_IP=$(openstack server show -f value -c addresses $username-wordpress-$i | awk -F '=' '{print $2}')
            openstack loadbalancer member create --subnet-id $SUBNET_ID --address $WP_IP --protocol-port 80 $username-http-pool
            openstack loadbalancer member create --subnet-id $SUBNET_ID --address $WP_IP --protocol-port 443 $username-https-pool
        done

        # Allocate a floating IP for the LB so students can reach it
        FLOATING_IP=$(openstack floating ip create -f value -c floating_ip_address provider-datacentre)
        LB_VIP_PORT_ID=$(openstack loadbalancer show $username-lb -f value -c vip_port_id)
        openstack floating ip set --port $LB_VIP_PORT_ID $FLOATING_IP

        echo "Load balancer for $username is ready at floating IP: $FLOATING_IP"



    elif [[ "$rola" == "student" ]]; then

        username="$ime.$prezime"
        projectname="$username-Student-Project"

        safe_base=$(echo "$username" | sed 's/[^A-Za-z0-9_-]/_/g')

        # Safe keypair names
        safe_jump_key="${safe_base}-JumpHost-key"
        safe_wp_key="${safe_base}-WordPress-key"
        safe_combined_key="${safe_base}-CombinedJumpHost-key"

        # Generate SSH keys (safe filenames)
        ssh-keygen -t rsa -b 2048 -f "$safe_jump_key" -N ""
        ssh-keygen -t rsa -b 2048 -f "$safe_wp_key" -N ""


        # Create OpenStack keypairs with safe names
        openstack keypair create --public-key "$safe_jump_key.pub" "$safe_jump_key"
        openstack keypair create --public-key "$safe_wp_key.pub" "$safe_wp_key"

        # Combine public keys and create combined keypair
        cat "$safe_jump_key.pub" "$safe_wp_key.pub" > "$safe_combined_key.pub"
        openstack keypair create --public-key "$safe_combined_key.pub" "$safe_combined_key"



        echo "Creating student JumpHost instance"

            openstack server create \
            --flavor Ubuntu-Server-Flavor \
            --image Ubuntu-Server \
            --nic net-id=$(openstack network show -f value -c id $username-private-network) \
            --security-group $username-jumphost-secgroup \
            --key-name $safe_combined_key \
            $username-jumphost

        echo "Creating WordPress instances for $username"

        for i in {1..4}; do 
            openstack server create \
                --flavor Ubuntu-Server-Flavor \
                --image Ubuntu-Server \
                --nic net-id=$(openstack network show -f value -c id $username-private-network) \
                --security-group $username-wordpress-secgroup \
                --key-name $safe_wp_key \
                --user-data cloud-init-wordpress.yaml \
                $username-wordpress-$i

        done

        SUBNET_ID=$(openstack subnet show -f value -c id $username-private-subnet)

        echo "Creating load balancer for $username in project $projectname"

        # Use private subnet for VIP (students connect here, external access via floating IP)
        openstack loadbalancer create \
            --name $username-lb \
            --vip-subnet-id $SUBNET_ID \
            --project $projectname

        # Wait for LB to become ACTIVE
        while true; do
            STATUS=$(openstack loadbalancer show $username-lb -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for load balancer $username-lb to become ACTIVE..."
            sleep 10
        done


        # Create HTTP listener and pool
        openstack loadbalancer listener create --name $username-http-listener --protocol HTTP --protocol-port 80 $username-lb
        while true; do
            STATUS=$(openstack loadbalancer listener show $username-http-listener -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for listener $username-http-listener to become ACTIVE..."
            sleep 10
        done
        openstack loadbalancer pool create --name $username-http-pool --lb $username-lb --listener $username-http-listener --protocol HTTP --lb-algorithm ROUND_ROBIN

        # Create HTTPS listener and pool
        openstack loadbalancer listener create --name $username-https-listener --protocol HTTPS --protocol-port 443 $username-lb
        while true; do
            STATUS=$(openstack loadbalancer listener show $username-https-listener -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for listener $username-https-listener to become ACTIVE..."
            sleep 10
        done
        openstack loadbalancer pool create --name $username-https-pool --lb $username-lb --listener $username-https-listener --protocol HTTPS --lb-algorithm ROUND_ROBIN

        # Create SSH listener and pool
        openstack loadbalancer listener create --name $username-ssh-listener --protocol TCP --protocol-port 22 $username-lb
        while true; do
            STATUS=$(openstack loadbalancer listener show $username-ssh-listener -f value -c provisioning_status)
            if [[ "$STATUS" == "ACTIVE" ]]; then break; fi
            echo "Waiting for listener $username-ssh-listener to become ACTIVE..."
            sleep 10
        done
        openstack loadbalancer pool create --name $username-ssh-pool --lb $username-lb --listener $username-ssh-listener --protocol TCP --lb-algorithm ROUND_ROBIN

        # Add JumpHost and WordPress instances as pool members (from student's private subnet)
        SUBNET_ID=$(openstack subnet show -f value -c id $username-private-subnet)
        # JumpHost
        JUMPHOST_IP=$(openstack server show -f value -c addresses $username-jumphost | awk -F '=' '{print $2}')
        openstack loadbalancer member create --subnet-id $SUBNET_ID --address $JUMPHOST_IP --protocol-port 22 $username-ssh-pool
        # WordPress
        for i in {1..4}; do
            WP_IP=$(openstack server show -f value -c addresses $username-wordpress-$i | awk -F '=' '{print $2}')
            openstack loadbalancer member create --subnet-id $SUBNET_ID --address $WP_IP --protocol-port 80 $username-http-pool
            openstack loadbalancer member create --subnet-id $SUBNET_ID --address $WP_IP --protocol-port 443 $username-https-pool
        done

        # Allocate a floating IP for the LB so students can reach it
        FLOATING_IP=$(openstack floating ip create -f value -c floating_ip_address provider-datacentre)
        LB_VIP_PORT_ID=$(openstack loadbalancer show $username-lb -f value -c vip_port_id)
        openstack floating ip set --port $LB_VIP_PORT_ID $FLOATING_IP

        echo "Load balancer for $username is ready at floating IP: $FLOATING_IP"

        fi
done < <(tail -n +2 Original_Popis_studenata.csv)
