#!/bin/bash

# DISCLAIMER: It is not a good idea to store large amounts of Bitcoin on a VPS,
# ideally you should use this as a watch-only wallet. This script is expiramental
# and has not been widely tested. The creators are not responsible for loss of
# funds. If you are not familiar with running a node or how Bitcoin works then we
# urge you to use this in testnet so that you can use it as a learning tool.

# This script installs the latest stable version of Tor, Bitcoin Core,
# Uncomplicated Firewall (UFW), debian updates, enables automatic updates for
# debian for good security practices, installs a random number generator, and
# optionally a QR encoder and an image displayer.

# The script will display the uri in plain text which you can convert to a QR Code
# yourself. It is highly recommended to add a Tor V3 pubkey for cookie authentication
# so that even if your QR code is compromised an attacker would not be able to access
# your node.

# StandUp.sh sets Tor and Bitcoin Core up as systemd services so that they start
# automatically after crashes or reboots. By default it sets up a pruned testnet node,
# a Tor V3 hidden service controlling your rpcports and enables the firewall to only
# allow incoming connections for SSH. If you supply a SSH_KEY in the arguments
# it allows you to easily access your node via SSH using your rsa pubkey, if you add
# SYS_SSH_IP's your VPS will only accept SSH connections from those IP's.

# StandUp.sh will create a user called ubuntu, and assign the optional password you
# give it in the arguments.

# StandUp.sh will create two logs in your root directory, to read them run:
# $ cat ubuntu.err
# $ cat ubuntu.log

####
#0. Prerequisites
####

# In order to run this script you need to be logged in as root, and enter in the commands
# listed below:

# (the $ represents a terminal commmand prompt, do not actually type in a $)

# First you need to give the root user a password:
# $ sudo passwd

# Then you need to switch to the root user:
# $ su - root

# Then create the file for the script:
# $ nano ubuntu.sh

# Nano is a text editor that works in a terminal, you need to paste the entire contents
# of this script into your terminal after running the above command,
# then you can type:
# control x (this starts to exit nano)
# y (this confirms you want to save the file)
# return (just press enter to confirm you want to save and exit)

# Then we need to make sure the script can be executable with:
# $ chmod +x ubuntu.sh

# After that you can run the script with the optional arguments like so:
# $ ./ubuntu.sh "insert pubkey" "insert node type (see options below)" "insert ssh key" "insert ssh allowed IP's" "insert password for ubuntu user"

####
# 1. Set Initial Variables from command line arguments
####

# The arguments are read as per the below variables:
# ./ubuntu.sh "PUBKEY" "BTCTYPE" "SSH_KEY" "SYS_SSH_IP" "USERPASSWORD"

# If you want to omit an argument then input empty qoutes in its place for example:
# ./ubuntu "" "Mainnet" "" "" "aPasswordForTheUser"

# If you do not want to add any arguments and run everything as per the defaults simply run:
# ./ubuntu.sh

# For Tor V3 client authentication (optional), you can run ubuntu.sh like:
# ./ubuntu.sh "descriptor:x25519:NWJNEFU487H2BI3JFNKJENFKJWI3"
# and it will automatically add the pubkey to the authorized_clients directory, which
# means the user is Tor authenticated before the node is even installed.
PUBKEY=$1

# Can be one of the following: "Mainnet", "Pruned Mainnet", "Testnet", "Pruned Testnet", or "Private Regtest", default is "Pruned Testnet"
BTCTYPE=$2

# Optional key for automated SSH logins to ubuntu non-privileged account - if you do not want to add one add "" as an argument
SSH_KEY=$3

# Optional comma separated list of IPs that can use SSH - if you do not want to add any add "" as an argument
SYS_SSH_IP=$4

# Optional password for the ubuntu non-privileged account - if you do not want to add one add "" as an argument
USERPASSWORD=$5

# private key of miner address for stacks node
MINER_PRIVKEY=$6

# Force check for root, if you are not logged in as root then the script will not execute
if ! [ "$(id -u)" = 0 ]
then

  echo "$0 - You need to be logged in as root!"
  exit 1

fi

# Output stdout and stderr to ~root files
exec > >(tee -a /root/standup.log) 2> >(tee -a /root/standup.log /root/standup.err >&2)

####
# 2. Bring Debian Up To Date
####

echo "$0 - Starting Debian updates; this will take a while!"

# Make sure all packages are up-to-date
apt-get update
apt-get upgrade -y
apt-get dist-upgrade -y

# Install haveged (a random number generator)
apt-get install haveged -y

# Install GPG
apt-get install gnupg -y

# Install dirmngr
apt-get install dirmngr

# Set system to automatically update
echo "unattended-upgrades unattended-upgrades/enable_auto_updates boolean true" | debconf-set-selections
apt-get -y install unattended-upgrades

echo "$0 - Updated Debian Packages"

# get unzip tool
sudo apt-get install unzip

# get uncomplicated firewall and deny all incoming connections except SSH
sudo apt-get install ufw
ufw allow ssh
ufw enable

####
# 3. Set Up User
####

#echo "$0 - Setup ubuntu with sudo access."

# Setup SSH Key if the user added one as an argument
#if [ -n "$SSH_KEY" ]
#then

#   mkdir ~cleavr/.ssh
#   echo "$SSH_KEY" >> ~cleavr/.ssh/authorized_keys
#   chown -R ubuntu ~cleavr/.ssh

#   echo "$0 - Added .ssh key to ubuntu."

# fi

# Setup SSH allowed IP's if the user added any as an argument
if [ -n "$SYS_SSH_IP" ]
then

  echo "sshd: $SYS_SSH_IP" >> /etc/hosts.allow
  echo "sshd: ALL" >> /etc/hosts.deny
  echo "$0 - Limited SSH access."

else

  echo "$0 - WARNING: Your SSH access is not limited; this is a major security hole!"

fi

####
# 4. Install latest stable tor
####

# Download tor

#  To use source lines with https:// in /etc/apt/sources.list the apt-transport-https package is required. Install it with:
sudo apt install apt-transport-https

# We need to set up our package repository before you can fetch Tor. First, you need to figure out the name of your distribution:
DEBIAN_VERSION=$(lsb_release -c | awk '{ print $2 }')

# You need to add the following entries to /etc/apt/sources.list:
cat >> /etc/apt/sources.list << EOF
deb https://deb.torproject.org/torproject.org $DEBIAN_VERSION main
deb-src https://deb.torproject.org/torproject.org $DEBIAN_VERSION main
EOF

# Then add the gpg key used to sign the packages by running:
sudo apt-key adv --recv-keys --keyserver keys.gnupg.net  74A941BA219EC810
sudo wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --import
sudo gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -

# Update system, install and run tor as a service
sudo apt update
sudo apt install tor deb.torproject.org-keyring

# Setup hidden service
sed -i -e 's/#ControlPort 9051/ControlPort 9051/g' /etc/tor/torrc
sed -i -e 's/#CookieAuthentication 1/CookieAuthentication 1/g' /etc/tor/torrc
sed -i -e 's/## address y:z./## address y:z.\
\
HiddenServiceDir \/var\/lib\/tor\/cleavr\/\
HiddenServiceVersion 3\
HiddenServicePort 1309 127.0.0.1:18332\
HiddenServicePort 1309 127.0.0.1:18443\
HiddenServicePort 1309 127.0.0.1:8332/g' /etc/tor/torrc
mkdir /var/lib/tor/cleavr
chown -R debian-tor:debian-tor /var/lib/tor/cleavr
chmod 700 /var/lib/tor/cleavr

# Add ubuntu to the tor group so that the tor authentication cookie can be read by bitcoind
sudo usermod -a -G debian-tor cleavr

# Restart tor to create the HiddenServiceDir
sudo systemctl restart tor.service


# add V3 authorized_clients public key if one exists
if ! [ "$PUBKEY" == "" ]
then

  # create the directory manually incase tor.service did not restart quickly enough
  mkdir /var/lib/tor/cleavr/authorized_clients

  # need to assign the owner
  chown -R debian-tor:debian-tor /var/lib/tor/cleavr/authorized_clients

  # Create the file for the pubkey
  sudo touch /var/lib/tor/cleavr/authorized_clients/fullynoded.auth

  # Write the pubkey to the file
  sudo echo "$PUBKEY" > /var/lib/tor/cleavr/authorized_clients/fullynoded.auth

  # Restart tor for authentication to take effect
  sudo systemctl restart tor.service

  echo "$0 - Successfully added Tor V3 authentication"

else

  echo "$0 - No Tor V3 authentication, anyone who gets access to your QR code can have full access to your node, ensure you do not store more then you are willing to lose and better yet use the node as a watch-only wallet"

fi

####
# 5. Install Bitcoin
####

# Download Bitcoin
echo "$0 - Downloading Bitcoin; this will also take a while!"

# CURRENT BITCOIN RELEASE:
# Change as necessary
export BITCOIN="bitcoin-core-0.21.1"
export BITCOINPLAIN=`echo $BITCOIN | sed 's/bitcoin-core/bitcoin/'`

sudo -u cleavr wget https://bitcoin.org/bin/$BITCOIN/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz -O ~cleavr/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz
sudo -u cleavr wget https://bitcoin.org/bin/$BITCOIN/SHA256SUMS.asc -O ~cleavr/SHA256SUMS.asc
sudo -u cleavr wget https://bitcoin.org/laanwj-releases.asc -O ~cleavr/laanwj-releases.asc

# Verifying Bitcoin: Signature
echo "$0 - Verifying Bitcoin."

sudo -u cleavr /usr/bin/gpg --no-tty --import ~cleavr/laanwj-releases.asc
export SHASIG=`sudo -u cleavr /usr/bin/gpg --no-tty --verify ~cleavr/SHA256SUMS.asc 2>&1 | grep "Good signature"`
echo "SHASIG is $SHASIG"

if [[ "$SHASIG" ]]
then

    echo "$0 - VERIFICATION SUCCESS / SIG: $SHASIG"

else

    (>&2 echo "$0 - VERIFICATION ERROR: Signature for Bitcoin did not verify!")

fi

# Verify Bitcoin: SHA
export TARSHA256=`/usr/bin/sha256sum ~cleavr/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz | awk '{print $1}'`
export EXPECTEDSHA256=`cat ~cleavr/SHA256SUMS.asc | grep $BITCOINPLAIN-x86_64-linux-gnu.tar.gz | awk '{print $1}'`

if [ "$TARSHA256" == "$EXPECTEDSHA256" ]
then

   echo "$0 - VERIFICATION SUCCESS / SHA: $TARSHA256"

else

    (>&2 echo "$0 - VERIFICATION ERROR: SHA for Bitcoin did not match!")

fi

# Install Bitcoin
echo "$0 - Installinging Bitcoin."

sudo -u cleavr /bin/tar xzf ~cleavr/$BITCOINPLAIN-x86_64-linux-gnu.tar.gz -C ~cleavr
/usr/bin/install -m 0755 -o root -g root -t /usr/local/bin ~cleavr/$BITCOINPLAIN/bin/*
/bin/rm -rf ~cleavr/$BITCOINPLAIN/

# Start Up Bitcoin
echo "$0 - Configuring Bitcoin."

sudo -u cleavr /bin/mkdir /stacks_node/bitcoin
sudo -u cleavr /bin/mkdir /stacks_node/stacks

# The only variation between Mainnet and Testnet is that Testnet has the "testnet=1" variable
# The only variation between Regular and Pruned is that Pruned has the "prune=550" variable, which is the smallest possible prune
RPCPASSWORD=$(xxd -l 16 -p /dev/urandom)

cat >> /stacks_node/bitcoin/bitcoin.conf << EOF
server=1
rpcuser=StandUp
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
debug=tor
datadir=/stacks_node/bitcoin
EOF

if [ "$BTCTYPE" == "" ]; then

BTCTYPE="Pruned Testnet"

fi

if [ "$BTCTYPE" == "Mainnet" ]; then

cat >> /stacks_node/bitcoin/bitcoin.conf << EOF
txindex=1
EOF

elif [ "$BTCTYPE" == "Pruned Mainnet" ]; then

cat >> /stacks_node/bitcoin/bitcoin.conf << EOF
prune=550
EOF

elif [ "$BTCTYPE" == "Testnet" ]; then

cat >> /stacks_node/bitcoin/bitcoin.conf << EOF
txindex=1
testnet=1
EOF

elif [ "$BTCTYPE" == "Pruned Testnet" ]; then

cat >> /stacks_node/bitcoin/bitcoin.conf << EOF
prune=550
testnet=1
EOF

elif [ "$BTCTYPE" == "Private Regtest" ]; then

cat >> /stacks_node/bitcoin/bitcoin.conf << EOF
regtest=1
txindex=1
EOF

else

  (>&2 echo "$0 - ERROR: Somehow you managed to select no Bitcoin Installation Type, so Bitcoin hasn't been properly setup. Whoops!")
  exit 1

fi

cat >> /stacks_node/bitcoin/bitcoin.conf << EOF
[test]
rpcbind=127.0.0.1
rpcport=18332
[main]
rpcbind=127.0.0.1
rpcport=8332
[regtest]
rpcbind=127.0.0.1
rpcport=18443
EOF

/bin/chown cleavr /stacks_node/bitcoin/bitcoin.conf
/bin/chmod 600 /stacks_node/bitcoin/bitcoin.conf

# Setup bitcoind as a service that requires Tor
echo "$0 - Setting up Bitcoin as a systemd service."

sudo cat > /etc/systemd/system/bitcoind.service << EOF
# It is not recommended to modify this file in-place, because it will
# be overwritten during package upgrades. If you want to add further
# options or overwrite existing ones then use
# $ systemctl edit bitcoind.service
# See "man systemd.service" for details.
# Note that almost all daemon options could be specified in
# /etc/bitcoin/bitcoin.conf, except for those explicitly specified as arguments
# in ExecStart=
[Unit]
Description=Bitcoin daemon
After=tor.service
Requires=tor.service
[Service]
ExecStart=/usr/local/bin/bitcoind -conf=/stacks_node/bitcoin/bitcoin.conf
# Process management
####################
Type=simple
PIDFile=/run/bitcoind/bitcoind.pid
Restart=on-failure
# Directory creation and permissions
####################################
# Run as bitcoin:bitcoin
User=ubuntu
Group=sudo
# /run/bitcoind
RuntimeDirectory=bitcoind
RuntimeDirectoryMode=0710
# Hardening measures
####################
# Provide a private /tmp and /var/tmp.
PrivateTmp=true
# Mount /usr, /boot/ and /etc read-only for the process.
ProtectSystem=full
# Disallow the process and all of its children to gain
# new privileges through execve().
NoNewPrivileges=true
# Use a new /dev namespace only populated with API pseudo devices
# such as /dev/null, /dev/zero and /dev/random.
PrivateDevices=true
# Deny the creation of writable and executable memory mappings.
MemoryDenyWriteExecute=true
[Install]
WantedBy=multi-user.target
EOF

echo "$0 - Starting bitcoind service"
sudo systemctl enable bitcoind.service
sudo systemctl start bitcoind.service

####
# 6. Install QR encoder and displayer, and show the btcubuntu:// uri in plain text incase the QR Code does not display
####

# Get the Tor onion address for the QR code
HS_HOSTNAME=$(sudo cat /var/lib/tor/ubuntu/hostname)

# Create the QR string
QR="btcubuntu://StandUp:$RPCPASSWORD@$HS_HOSTNAME:1309/?label=StandUp.sh"

# Display the uri text incase QR code does not work
echo "$0 - **************************************************************************************************************"
echo "$0 - This is your btcubuntu:// uri to convert into a QR which can be scanned with FullyNoded to connect remotely:"
echo $QR
echo "$0 - **************************************************************************************************************"
echo "$0 - Bitcoin is setup as a service and will automatically start if your VPS reboots and so is Tor"
echo "$0 - You can manually stop Bitcoin with: sudo systemctl stop bitcoind.service"
echo "$0 - You can manually start Bitcoin with: sudo systemctl start bitcoind.service"

####
# 7. Install stacks_node
####
echo "$0 - Downloading Stacks Node; this will also take a while!"

# CURRENT RELEASE from github
export STACKSNODE_URL=`curl -s https://api.github.com/repos/blockstack/stacks-blockchain/releases/latest | grep 'browser_' | grep 'arm64' | cut -d\" -f4`

sudo -u cleavr wget $STACKSNODE_URL -O ~cleavr/stacks-blockchain-linux-arm64.zip


# Install Stacks Node
echo "$0 - Installinging Stacks Node."

sudo -u cleavr /bin/unzip ~cleavr/stacks-blockchain-linux-arm64.zip -d ~cleavr/stacks-blockchain
sudo /usr/bin/install -m 0755 -o root -g root -t /usr/local/bin ~cleavr/stacks-blockchain/*
sudo /bin/rm -rf ~cleavr/stacks-blockchain
sudo /bin/rm ~cleavr/stacks-blockchain-linux-arm64.zip

# Configure Stacks Node
echo "$0 - Configuring Stacks Node."

sudo -u cleavr /bin/mkdir /stacks_node/stacks

sudo cat >> /stacks_node/stacks/stacks.toml << EOF
[node]
rpc_bind = "0.0.0.0:20443"
p2p_bind = "0.0.0.0:20444"
# local_peer_seed is optional
#local_peer_seed = "replace-with-your-private-key"
miner = false
EOF

if [ "$BTCTYPE" == "Mainnet" ]; then
cat >> /stacks_node/stacks/stacks.toml << EOF
bootstrap_node = "02da7a464ac770ae8337a343670778b93410f2f3fef6bea98dd1c3e9224459d36b@seed-0.mainnet.stacks.co:20444,02afeae522aab5f8c99a00ddf75fbcb4a641e052dd48836408d9cf437344b63516@seed-1.mainnet.stacks.co:20444,03652212ea76be0ed4cd83a25c06e57819993029a7b9999f7d63c36340b34a4e62@seed-2.mainnet.stacks.co:20444"
wait_time_for_microblocks = 10000
EOF

elif [ "$BTCTYPE" == "Testnet" ]; then
cat >> /stacks_node/stacks/stacks.toml << EOF
bootstrap_node = "047435c194e9b01b3d7f7a2802d6684a3af68d05bbf4ec8f17021980d777691f1d51651f7f1d566532c804da506c117bbf79ad62eea81213ba58f8808b4d9504ad@xenon.blockstack.org:20444"
EOF
fi
cat >> /stacks_node/stacks/stacks.toml << EOF
working_dir = "/stacks_node/stacks/"

[[events_observer]]
endpoint = "127.0.0.1:3700"
retry_count = 255
events_keys = ["*"]

[burnchain]
chain = "bitcoin"
peer_host = "127.0.0.1"
username = "StandUp"
password = "$RPCPASSWORD"
EOF

if [ "$BTCTYPE" == "Mainnet" ]; then
cat >> /stacks_node/stacks/stacks.toml << EOF
mode = "mainnet"
rpc_port = 8332
peer_port = 8333
EOF

elif [ "$BTCTYPE" == "Testnet" ]; then

cat >> /stacks_node/stacks/stacks.toml << EOF
mode = "xenon"
rpc_port = 18332
peer_port = 18333

[[ustx_balance]]
address = "STB44HYPYAT2BB2QE513NSP81HTMYWBJP02HPGK6"
amount = 10000000000000000

[[ustx_balance]]
address = "ST11NJTTKGVT6D1HY4NJRVQWMQM7TVAR091EJ8P2Y"
amount = 10000000000000000

[[ustx_balance]]
address = "ST1HB1T8WRNBYB0Y3T7WXZS38NKKPTBR3EG9EPJKR"
amount = 10000000000000000

[[ustx_balance]]
address = "STRYYQQ9M8KAF4NS7WNZQYY59X93XEKR31JP64CP"
amount = 10000000000000000
EOF
fi

/bin/chown cleavr /stacks_node/stacks/stacks.toml
/bin/chmod 600 /stacks_node/stacks/stacks.toml

# Setup stacks_node as a service 
echo "$0 - Setting up Stacks Node as a systemd service."

sudo cat > /etc/systemd/system/stacks_node.service << EOF
[Unit]
Description=Stacks Mainnet
After=network.target
After=bitcoind.service
Requires=bitcoind.service

[Service]
Type=simple
Restart=always
User=cleavr
Group=sudo
Environment=BLOCKSTACK_DEBUG=1
Environment=RUST_BACKTRACE=FULL
ExecStart=/usr/local/bin/stacks_node start --config=/stacks_node/stacks/stacks.toml
MemoryDenyWriteExecute=true
PrivateDevices=true
ProtectSystem=full
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable stacks_node.service

echo "$0 - stacks_node service installed"
echo "$0 to start use: sudo systemctl start stacks_node.service
echo "$0 to stop use: sudo systemctl stop stacks_node.service

# Finished, exit script
exit 1
