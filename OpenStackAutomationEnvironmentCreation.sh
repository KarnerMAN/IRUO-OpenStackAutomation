#!/bin/bash

# Defining Variables
tagdefault="course:test"

# Starting the Script

source ~/admin-rc

echo "Creation of OpenStack Environment Started"
echo

openstack network set --description "Shared external network for CloudLearn" --tag $tagdefault provider-datacentre

echo "Creating new OpenStack domain named CloudLearnDomain"
openstack domain create --description "Domain for CloudLearn" CloudLearnDomain 

echo "Creating new project named CloudLearn"
openstack project create --domain CloudLearnDomain --description "Project for CloudLearn" CloudLearn --tag $tagdefault

echo "Creating Student group and Instructor group"
openstack group create --domain CloudLearnDomain --description "Group for Students" StudentGroup 
openstack group create --domain CloudLearnDomain --description "Group for Instructors" InstructorGroup 

# Wait for groups to exist
for i in {1..10}; do
    openstack group show StudentGroup && break
    echo "Waiting for Student Group to be available..."
    sleep 2
done

for i in {1..10}; do
    openstack group show InstructorGroup && break
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
    if [ "$rola" == "student" ]; then
        projectname="$username-Student-Project"

        echo "Adding user to student group"
        openstack group add user StudentGroup $username

        echo "Creating project for student"
        openstack project create --domain CloudLearnDomain --parent CloudLearn --description "Project for $ime $prezime" $projectname --tag $tagdefault

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
        --tag $tagdefault
        openstack router add subnet $username-router $username-private-subnet
        openstack router set --external-gateway provider-datacentre $username-router

        echo "Creating security group and rules for $username"
        openstack security group create \
        --project $projectname \
        --description "Security group for $username" \
        $username-secgroup \
        --tag $tagdefault
        
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol icmp --ingress --description "Allow ICMP" $username-secgroup
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 22 --ingress --description "Allow SSH" $username-secgroup
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 80 --ingress --description "Allow HTTP" $username-secgroup

        openstack role add --project $projectname --user $username admin
    elif [ "$rola" == "instructor" ]; then
        projectname="$username-Instructor-Project"

        echo "Adding user to instructor group"
        openstack group add user InstructorGroup $username

        echo "Creating project for instructor"
        openstack project create --domain CloudLearnDomain --parent CloudLearn --description "Project for $ime $prezime" $projectname --tag $tagdefault

        openstack role add --project $projectname --user $username admin

        echo "Creating a private network for instructor $username"
        openstack network create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --no-share \
        --description "Private network for $username" \
        --tag $tagdefault \
        $username-private-network

        echo "Creating the subnet for the private network"
        openstack subnet create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --network $username-private-network \
        --subnet-range 192.168.0.0/24 \
        --description "Private subnet for $username" \
        --tag $tagdefault \
        $username-private-subnet

        echo "Creating router for $username"
        openstack router create \
        --project $projectname \
        --project-domain CloudLearnDomain \
        --description "Router for $username" \
        $username-router \
        --tag $tagdefault

        openstack router add subnet $username-router $username-private-subnet
        openstack router set --external-gateway provider-datacentre $username-router

        echo "Creating security group and rules for $username"
        openstack security group create \
        --project $projectname \
        --description "Security group for $username" \
        $username-secgroup \
        --tag $tagdefault

        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol icmp --ingress --description "Allow ICMP" $username-secgroup
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 22 --ingress --description "Allow SSH" $username-secgroup
        openstack security group rule create --project $projectname --project-domain CloudLearnDomain --protocol tcp --dst-port 80 --ingress --description "Allow HTTP" $username-secgroup

        echo "$username" >> $allinstructors
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

wget https://cloud-images.ubuntu.com/daily/server/jammy/current/jammy-server-cloudimg-amd64.img

openstack image create \
--file jammy-server-cloudimg-amd64.img \
--disk-format qcow2 \
--container-format bare \
--public \
--tag $tagdefault \
--description "Ubuntu server cloud image" \
Ubuntu-Server-Image

openstack flavor create \
--ram 1024 \
--disk 16 \
--ephemeral 16 \
--vcpus 1 \
--public \
--description "Flavor for Ubuntu server instances" \
Ubuntu-Server-Flavor

tail -n +2 Original_Popis_studenata.csv | while IFS=';' read -r ime prezime rola
do
    if [ "$rola" == "instructor" ]; then
    username="$ime.$prezime"

    # Creating SSH key for each instructor
    ssh-keygen -t rsa -b 2048 -f $username-JumpHost-key -N ""

    ssh-keygen -t rsa -b 2048 -f $username-WordPress-key -N ""

    openstack keypair create \
    --user $username \
    --project-domain CloudLearnDomain \
    --public-key $username-JumpHost-key.pub \
    $username-JumpHost-key

    openstack keypair create \
    --user $username \
    --project-domain CloudLearnDomain \
    --public-key $username-WordPress-key.pub \
    $username-WordPress-key

    echo "Creating JumpHost for instructor $username"

    openstack server create \
        --project "$username-Instructor-Project" \
        --flavor Ubuntu-Server-Flavor \
        --image Ubuntu-Server-Image \
        --nic net-id=$(openstack network show -f value -c id $username-private-network) \
        --security-group $username-secgroup \
        --key-name $username-JumpHost-key \
        --min 1 --max 1 \
        --description "JumpHost for $username" \
        $username-jumphost




    fi
done
