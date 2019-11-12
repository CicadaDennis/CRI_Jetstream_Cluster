#!/bin/bash

source /etc/slurm/openrc.sh

node_size="m1.small"
node_image=$(openstack image list -f value | grep -i ${OS_USERNAME}-compute-image- | cut -f 2 -d' '| tail -n 1)
key_name="${OS_USERNAME}-${OS_PROJECT_NAME}-slurm-key"
network_name=${OS_USERNAME}-elastic-net
log_loc=/var/log/slurm/slurm_elastic.log

echo "Node resume invoked: $0 $*" >> $log_loc

#useradd won't do anything if the user exists. 
echo "#!/bin/bash" > /tmp/add_users.sh
cat /etc/passwd | awk -F':' '$4 >= 1001 && $4 < 65000 {print "useradd -M -u", $3, $1}' >> /tmp/add_users.sh

#First, loop over hosts and run the openstack create commands for *all* resume hosts at once.
for host in $(scontrol show hostname $1)
do
#  echo "$host ansible_user=centos ansible_become=true" >> /etc/ansible/hosts

#  echo "openstack server create $host --flavor $node_size --image $node_image --key-name $key_name --user-data <(cat /etc/slurm/prevent-updates.ci && echo -e "hostname: $host \npreserve_hostname: true\ndebug:") --security-group global-ssh --security-group cluster-internal --nic net-id=$network_name" >> $log_loc

#Let's spawn a bunch of subtasks!
    (echo "creating $host" >> $log_loc;
    openstack server create $host \
    --flavor $node_size \
    --image $node_image \
    --key-name $key_name \
    --user-data <(cat /etc/slurm/prevent-updates.ci && echo -e "hostname: $host \npreserve_hostname: true\ndebug:") \
    --security-group ${OS_USERNAME}-global-ssh --security-group ${OS_USERNAME}-cluster-internal \
    --nic net-id=$network_name 2>&1 \
    | tee -a $log_loc | awk '/status/ {print $4}' >> $log_loc 2>&1;

  node_status="UNKOWN";
  until [[ $node_status == "ACTIVE" ]]; do
    node_state=$(openstack server show $host 2>&1);
    node_status=$(echo -e "${node_state}" | awk '/status/ {print $4}');
#    echo "$host status is: $node_status" >> $log_loc;
#    echo "$host ip is: $node_ip" >> $log_loc;
    sleep 3;
  done;
  node_ip=$(echo -e "${node_state}" | awk '/addresses/ {print gensub(/^.*=/,"","g",$4)}');

  echo "$host ip is $node_ip" >> $log_loc;
  scontrol update nodename=$host nodeaddr=$node_ip >> $log_loc;)&
  sleep 2 # don't send all the JS requests at "once"
done
