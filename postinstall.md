Connect to VScode
Connect to chrome
Setup OBS using scripts
check for screen tearing.
LX theme : breeze-dark , noto sans nerdfont 10
select icon themes breeze-
dark
Set default pulse select

Add bluetooth mouse.
 
 bluetoothctl power on
 bluetoothctl discoverable on
 bluetoothctl pairable on
 bluetoothctl scan on
 bluetoothctl devices
 bluetoothctl pair 3C:4D:BE:84:1F:BC
 bluetoothctl connect 3C:4D:BE:84:1F:BC
 bluetoothctl disconnect 3C:4D:BE:84:1F:BC



setup git default
git config --global core.editor "vim"
git config --global user.name apham
git config --global user.email apham@${HOSTNAME}

on dell g15
echo "options  iwlwifi  enable_ini=0" > /etc/modprobe.d/iwlwifi.conf ;
systemctl reboot;

/etc/modprobe.d/iwlwifi.conf




image=debian-12-generic-amd64
variant=debiantesting

vmcr master 4096 4 $image 10 40G 1G $variant
vmcr node01 2048 4 $image 11 40G 1G $variant
vmcr node02 2048 4 $image 12 40G 1G $variant
vmcr node03 2048 4 $image 13 40G 1G $variant

vmcr v8s 12288 8 debian-12-generic-amd64 20 40G 1G debiantesting
vmcr sandbox 6144 4 debian-12-generic-amd64 50 40G 1G debiantesting

vmcr bmg 6144 8 d12-kube 50 40G 1G debiantesting
vmcr v8s 12288 8 d12-kube 20 40G 1G debiantesting


rm -rf /home/${USER}/apps/tls
mkdir -p /home/${USER}/apps/tls/cfg /home/${USER}/apps/tls/logs

docker run --rm --name certbot  -v "/home/${USER}/apps/tls/cfg:/etc/letsencrypt" -v "/home/${USER}/apps/tls/logs:/var/log/letsencrypt" infinityofspace/certbot_dns_duckdns:${CERTBOT_DUCKDNS_VERSION} \
   certonly \
     --non-interactive \
     --agree-tos \
     --email ${EMAIL} \
     --preferred-challenges dns \
     --authenticator dns-duckdns \
     --dns-duckdns-token ${DUCKDNS_TOKEN} \
     --dns-duckdns-propagation-seconds 20 \
     -d "*.${WILDCARD_DOMAIN}"

sudo chown -R ${USER}:${USER} /home/${USER}/apps/tls/cfg

openssl pkcs12 -export -out /home/${USER}/apps/tls/cfg/live/${WILDCARD_DOMAIN}/privkey.p12  -in /home/${USER}/apps/tls/cfg/live/${WILDCARD_DOMAIN}/fullchain.pem -inkey  /home/${USER}/apps/tls/cfg/live/${WILDCARD_DOMAIN}/privkey.pem -passin pass:password -passout pass:password


curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit



VERSION="v1.32.0"
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-$VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$VERSION-linux-amd64.tar.gz


macbook keyboard 

```sh
# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="apple_laptop"
XKBLAYOUT="fr"
XKBVARIANT="mac"
XKBOPTIONS=""

BACKSPACE="guess"
```