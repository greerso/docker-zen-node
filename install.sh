#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

print_status() {
    echo -e
    echo -e "## $1"
    echo -e
}

if [ $# -lt 4 ]; then
    echo -e "Execution format ./install.sh stakeaddr email fqdn region nodetype"
    exit
fi

# Installation variables
stakeaddr=${1}
email=${2}
fqdn=${3}
region=${4}

if [ -z "$5" ]; then
  nodetype="secure"
else
  nodetype=${5}
fi

testnet=0
rpcpassword=$(head -c 32 /dev/urandom | base64)

print_status "Installing the ZenCash node..."

echo -e "#########################"
echo -e "fqdn: $fqdn"
echo -e "email: $email"
echo -e "stakeaddr: $stakeaddr"
echo -e "#########################"

createswap() {
  # Create swapfile if less then 4GB memory
  totalmem=$(free -m | awk '/^Mem:/{print $2}')
  totalswp=$(free -m | awk '/^Swap:/{print $2}')
  totalm=$(($totalmem + $totalswp))
  if [ $totalm -lt 4000 ]; then
    print_status "Server memory is less then 4GB..."
    if ! grep -q '/swapfile' /etc/fstab ; then
      print_status "Creating a 4GB swapfile..."
      fallocate -l 4G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo -e '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  fi
}

populateaptcache() {
  # Populating Cache
  print_status "Populating apt cache..."
  apt update
}

installdocker() {
  # Install Docker
  if ! hash docker 2>/dev/null; then
    print_status "Installing Docker..."
    apt -y remove docker docker-engine docker.io containerd runc > /dev/null 2>&1
    apt -y install \
      apt-transport-https \
      ca-certificates \
      curl \
      gnupg-agent \
      lsb-release \
      software-properties-common \
      > /dev/null 2>&1
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    apt-key fingerprint 0EBFCD88
    add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
    apt-get update
    apt-get -y install \
      docker-ce \
      docker-ce-cli \
      containerd.io
      > /dev/null 2>&1
    systemctl enable docker
    systemctl start docker
  fi
}

installdependencies() {
  print_status "Installing packages required for setup..."
  apt -y install \
  unattended-upgrades \
  dnsutils \
  > /dev/null 2>&1
}

createdirs() {
  print_status "Creating the docker mount directories..."
  mkdir -p /mnt/zen/{config,data,zcash-params,certs}
}

installcertbot() {
  print_status "Removing acme container service..."
  rm /etc/systemd/system/acme-sh.service

  print_status "Disable apache2 and/or nginx if enabled, to free Port 80..."
  systemctl disable apache2
  systemctl stop apache2
  systemctl disable nginx
  systemctl stop nginx

  print_status "Installing certbot..."
  add-apt-repository ppa:certbot/certbot -y
  apt update -y  > /dev/null 2>&1
  apt install certbot -y > /dev/null 2>&1

  print_status "Issusing cert for $fqdn..."
  certbot certonly -n --agree-tos --register-unsafely-without-email --standalone -d $fqdn

  chmod -R 755 /etc/letsencrypt/
}

zenupdate() {
  echo -e \
  "[Unit]
  Description=zenupdate.service

  [Service]
  Type=oneshot
  ExecStart=/usr/bin/certbot -q renew --deploy-hook 'systemctl restart zen-node && systemctl restart zen-secnodetracker && docker rmi $(docker images --quiet --filter "dangling=true")'
  PrivateTmp=true" | tee /lib/systemd/system/zenupdate.service

  echo -e \
  "[Unit]
  Description=Run zenupdate unit daily @ 06:00:00 (UTC)

  [Timer]
  OnCalendar=*-*-* 06:00:00
  Unit=zenupdate.service
  Persistent=true

  [Install]
  WantedBy=timers.target" | tee /lib/systemd/system/zenupdate.timer

  systemctl daemon-reload
  systemctl stop certbot.timer
  systemctl disable certbot.timer

  systemctl start zenupdate.timer
  systemctl enable zenupdate.timer
}

zenconfig() {
  print_status "Creating the zen configuration."
  echo -e \
  "rpcport=18231
  rpcallowip=127.0.0.1
  rpcworkqueue=512
  server=1
  # Docker doesn't run as daemon
  daemon=0
  listen=1
  txindex=1
  logtimestamps=1
  ### testnet config
  testnet=$testnet
  rpcuser=user
  rpcpassword=$rpcpassword
  tlscertpath=/etc/letsencrypt/live/$fqdn/cert.pem
  tlskeypath=/etc/letsencrypt/live/$fqdn/privkey.pem
  #
  port=9033" | tee /mnt/zen/config/zen.conf

  print_status "Trying to determine public ip addresses..."
  publicips=$(dig $fqdn A $fqdn AAAA +short)
  while read -r line; do
      echo -e "externalip=$line" >> /mnt/zen/config/zen.conf
  done <<< "$publicips"
}
secnodeconfig() {
  print_status "Creating the secnode config..."

  if [ $nodetype = "super" ]; then
    servers=xns
  else
    servers=ts
  fi

  mkdir -p /mnt/zen/secnode/
  echo -e \
 " {
    \"active\": \"$nodetype\",
    \"$nodetype\": {
      \"nodetype\": \"$nodetype\",
      \"nodeid\": null,
      \"servers\": [
      \"${servers}2.eu\",
      \"${servers}1.eu\",
      \"${servers}3.eu\",
      \"${servers}4.eu\",
      \"${servers}4.na\",
      \"${servers}3.na\",
      \"${servers}2.na\",
      \"${servers}1.na\"
      ],
      \"stakeaddr\": \"$stakeaddr\",
      \"email\": \"$email\",
      \"fqdn\": \"$fqdn\",
      \"ipv\": \"4\",
      \"region\": \"$region\",
      \"home\": \"${servers}1.$region\",
      \"category\": \"none\"
    }
  }" | tee /mnt/zen/secnode/config.json
}

zendservice() {
  print_status "Installing zend service..."
  echo -e \ 
  "[Unit]
  Description=Zen Daemon Container
  After=docker.service
  Requires=docker.service

  [Service]
  TimeoutStartSec=10m
  Restart=always
  ExecStartPre=-/usr/bin/docker stop zen-node
  ExecStartPre=-/usr/bin/docker rm  zen-node
  # Always pull the latest docker image
  ExecStartPre=/usr/bin/docker pull greerso/zend:latest
  ExecStart=/usr/bin/docker run --rm --net=host -p 9033:9033 -p 18231:18231 -v /mnt/zen:/mnt/zen -v /etc/letsencrypt/:/etc/letsencrypt/ --name zen-node greerso/zend:latest
  [Install]
  WantedBy=multi-user.target" | tee /etc/systemd/system/zen-node.service
}

trackerservice() {
  print_status "Installing secnodetracker service..."
  echo -e \
  "[Unit]
  Description=Zen Secnodetracker Container
  After=docker.service
  Requires=docker.service

  [Service]
  TimeoutStartSec=10m
  Restart=always
  ExecStartPre=-/usr/bin/docker stop zen-secnodetracker
  ExecStartPre=-/usr/bin/docker rm  zen-secnodetracker
  # Always pull the latest docker image
  ExecStartPre=/usr/bin/docker pull greerso/secnodetracker:latest
  #ExecStart=/usr/bin/docker run --init --rm --net=host -v /mnt/zen:/mnt/zen --name zen-secnodetracker greerso/secnodetracker:latest
  ExecStart=/usr/bin/docker run --rm --net=host -v /mnt/zen:/mnt/zen --name zen-secnodetracker greerso/secnodetracker:latest
  [Install]
  WantedBy=multi-user.target" | tee /etc/systemd/system/zen-secnodetracker.service
}

startcontainers() {
  print_status "Enabling and starting container services..."
  systemctl daemon-reload
  systemctl enable zen-node
  systemctl restart zen-node

  systemctl enable zen-secnodetracker
  systemctl restart zen-secnodetracker
}

zenalias() {
  if ! grep -q "alias zen-cli" ~/.aliases ; then
    echo -e "alias zen-cli=\"docker exec -it zen-node /usr/local/bin/gosu user zen-cli\"" | tee -a ~/.aliases
  fi
  
  if ! grep -q ". ~/.aliases" ~/.bashrc ; then
    echo -e \
    "if [ -f ~/.aliases ]; then
      . ~/.aliases
    fi" | tee -a ~/.bashrc
  fi

  if ! grep -q "source $HOME/.aliases" ~/.zshrc ; then
    echo -e "source $HOME/.aliases" | tee -a ~/.zshrc
  fi

  source ~/.aliases
}

fetchparams() {
  print_status "Waiting for node to fetch params ..."
  until docker exec -it zen-node /usr/local/bin/gosu user zen-cli getinfo
  do
    echo -e ".."
    sleep 30
  done
}

getzaddr() {
  if [[ $(docker exec -it zen-node /usr/local/bin/gosu user zen-cli z_listaddresses | wc -l) -eq 2 ]]; then
    print_status "Generating shield address for node... you will need to send 1 ZEN to this address:"
    docker exec -it zen-node /usr/local/bin/gosu user zen-cli z_getnewaddress

    print_status "Restarting secnodetracker"
    systemctl restart zen-secnodetracker
  else
    print_status "Node already has shield address... you will need to send 1 ZEN to this address:"
    docker exec -it zen-node /usr/local/bin/gosu user zen-cli z_listaddresses
  fi
}

createswap
populateaptcache
installdocker
installdependencies
createdirs
installcertbot
zenupdate
zenconfig
secnodeconfig
zendservice
trackerservice
startcontainers
fetchparams
getzaddr

print_status "Install Finished"
echo -e "Please wait until the blocks are up to date..."

## TODO: Post the shield address back to our API
