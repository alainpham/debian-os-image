#!/bin/bash
inputversions() {
    # https://github.com/docker/buildx/releases
    export DOCKER_BUILDX_VERSION=v0.20.1
    echo "export DOCKER_BUILDX_VERSION=${DOCKER_BUILDX_VERSION}"
    
    # https://kubernetes.io/releases/  https://cloud.google.com/kubernetes-engine/docs/release-notes
    export MAJOR_KUBE_VERSION=v1.30
    echo "export MAJOR_KUBE_VERSION=${MAJOR_KUBE_VERSION}"
    
    # https://github.com/derailed/k9s/releases
    export K9S_VERSION=v0.32.7
    echo "export K9S_VERSION=${K9S_VERSION}"
    
    # https://maven.apache.org/download.cgi
    export MVN_VERSION=3.9.9
    echo "export MVN_VERSION=${MVN_VERSION}"

    export NERDFONTS="ComicShannsMono FiraMono JetBrainsMono Overpass Noto "
    echo "export NERDFONTS=${NERDFONTS}"

    # https://zoom.us/download?os=linux
    export ZOOM_VERSION=6.3.6.6315
    echo "export ZOOM_VERSION=${ZOOM_VERSION}"
    
    # https://mlv.app/
    export MLVAPP_VERSION=1.14
    echo "export MLVAPP_VERSION=${MLVAPP_VERSION}"

    # https://beeref.org/
    export BEEREF_VERSION=0.3.3
    echo "export BEEREF_VERSION=${BEEREF_VERSION}"

    # https://www.freac.org/downloads-mainmenu-33
    export FREAC_VERSION=1.1.7
    echo "export FREAC_VERSION=${FREAC_VERSION}"

    # https://github.com/IsmaelMartinez/teams-for-linux/releases/latest
    export TEAMS_VERSION=1.12.5
    echo "export TEAMS_VERSION=${TEAMS_VERSION}"

    # https://github.com/sindresorhus/caprine/releases/tag/v2.60.3
    export CAPRINE_VERSION=2.60.3
    echo "export CAPRINE_VERSION=${CAPRINE_VERSION}"

    # https://github.com/jgraph/drawio-desktop/releases
    export DRAWIO_VERSION=26.0.4
    echo "export DRAWIO_VERSION=${DRAWIO_VERSION}"

    # https://hub.docker.com/r/infinityofspace/certbot_dns_duckdns/tags
    export CERTBOT_DUCKDNS_VERSION=v1.5
    echo "export CERTBOT_DUCKDNS_VERSION=${CERTBOT_DUCKDNS_VERSION}"

    export OSNAME=$(awk -F= '/^ID=/ {gsub(/"/, "", $2); print $2}' /etc/os-release)
    echo "export OSNAME=${OSNAME}"
}

inputkeyboard() {
    export KEYBOARD_LAYOUT=fr
    echo "export KEYBOARD_LAYOUT=${KEYBOARD_LAYOUT}"
}


inputtasks() {
    #default root
    
    export ROOTFS=/
    echo "export ROOTFS=${ROOTFS}"

    # Map input parameters
    export OPERATION=$1
    echo "export OPERATION=${OPERATION}"
    export TARGET_USERNAME=${2:-apham}
    echo "export TARGET_USERNAME=${TARGET_USERNAME}"
    export TARGET_PASSWD=$3
    echo "export TARGET_PASSWD=${TARGET_PASSWD}"
    export AUTHSSHFILE=$4
    echo "export AUTHSSHFILE=${AUTHSSHFILE}"
    export INPUT_IMG=$5
    echo "export INPUT_IMG=${INPUT_IMG}"
    export OUTPUT_IMAGE=$6
    echo "export OUTPUT_IMAGE=${OUTPUT_IMAGE}"
    export DISK_SIZE=$7
    echo "export DISK_SIZE=${DISK_SIZE}"
    

}

lineinfile() {
    local file_path="$1"   # First argument: file path
    local regex="$2"       # Second argument: regex to search for
    local new_line="$3"    # Third argument: new line to replace or add
    local create_file="$4" # Fourth argument: create file if not found

    if [ -z "$create_file" ]; then
        create_file=0
    fi

    # Check if the file exists
    if [ ! -f "$file_path" ]; then
        if [ $create_file -eq 1 ]; then
            echo "File not found creating file !"
            touch "$file_path"
        else
            return 1
        fi
    fi

    # Check if the line matching the regex exists in the file
    if grep -qE "$regex" "$file_path"; then
        # If found, replace the matching line
        sed -i "s]$regex]$new_line]" "$file_path"
        echo "Line matching '$regex' was replaced."
    else
        # If not found, append the new line at the end of the file
        echo "$new_line" >> "$file_path"
        echo "New line added : $new_line"
    fi
    
}

mountraw() {
    # Only execute when working with a raw image
    if [ $INSIDE_MACHINE -eq 0 ]; then

    # name devices
    export DEVICE=/dev/loop0
    export ROOTFS="/tmp/installing-rootfs"

    # resize image
    cp $INPUT_IMG $OUTPUT_IMAGE
    qemu-img  resize -f raw $OUTPUT_IMAGE $DISK_SIZE

    # setup loopback
    losetup -D 
    losetup -fP $OUTPUT_IMAGE

    # fix partition
    printf "fix\n" | parted ---pretend-input-tty $DEVICE print
    growpart ${DEVICE} 1
    resize2fs ${DEVICE}p1

    # mount image for chroot
    echo "Mount OS partition"
    mkdir -p ${ROOTFS}
    mount ${DEVICE}p1 ${ROOTFS}
    mount ${DEVICE}p15 ${ROOTFS}/boot/efi

    echo "Get ready for chroot"
    mount --bind /dev ${ROOTFS}/dev
    mount --bind /run ${ROOTFS}/run

    mount -t devpts /dev/pts ${ROOTFS}/dev/pts
    mount -t proc proc ${ROOTFS}/proc
    mount -t sysfs sysfs ${ROOTFS}/sys
    mount -t tmpfs tmpfs ${ROOTFS}/tmp
    fi 
}

createuser() {
echo "setup users"
cat << EOF | chroot ${ROOTFS}
    /usr/sbin/useradd -m -s /bin/bash $TARGET_USERNAME
    mkdir -p /home/${TARGET_USERNAME}/.ssh
    if [ ! -f /home/${TARGET_USERNAME}/.ssh/id_rsa ]; then
        ssh-keygen -N "" -f /home/${TARGET_USERNAME}/.ssh/id_rsa
    fi
    chown -R ${TARGET_USERNAME}:${TARGET_USERNAME} /home/${TARGET_USERNAME}/.ssh
EOF

}

setpasswd() {

export TARGET_ENCRYPTED_PASSWD=$(openssl passwd -6 -salt xyz $TARGET_PASSWD)
echo "setup users"
cat << EOF | chroot ${ROOTFS}
    echo '${TARGET_USERNAME}:${TARGET_ENCRYPTED_PASSWD}' | /usr/sbin/chpasswd -e
    echo 'root:${TARGET_ENCRYPTED_PASSWD}' | /usr/sbin/chpasswd -e
EOF

}

authkeys() {

mkdir -p ${ROOTFS}/home/$TARGET_USERNAME/.ssh/
echo "Copy authorized_keys $AUTHSSHFILE"
cp $AUTHSSHFILE ${ROOTFS}/home/$TARGET_USERNAME/.ssh/authorized_keys
cat << EOF | chroot ${ROOTFS}
    chown $TARGET_USERNAME:$TARGET_USERNAME -R /home/$TARGET_USERNAME/.ssh
EOF

echo "Copied authorized_keys"

}

rmnouveau() {

# deactivate nouveau drivers 
sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/ {/modprobe.blacklist=nouveau/! s/"$/ modprobe.blacklist=nouveau"/}' ${ROOTFS}/etc/default/grub

echo $OSNAME

if [ "$OSNAME" = "debian" ]; then
cat << EOF | chroot ${ROOTFS}
    update-grub
EOF
fi

if [ "$OSNAME" = "openmandriva" ]; then
cat << EOF | chroot ${ROOTFS}
    if [ -d /sys/firmware/efi ]; then 
        sudo grub2-mkconfig -o /boot/efi/EFI/openmandriva/grub.cfg
    else 
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
EOF
fi

echo "Deactivated nouveau drivers"

}

fastboot() {

if [ "$OSNAME" = "debian" ]; then
echo debian
# accelerate grub startup
mkdir -p ${ROOTFS}/etc/default/grub.d/
echo 'GRUB_TIMEOUT=0' | tee ${ROOTFS}/etc/default/grub.d/15_timeout.cfg
cat << EOF | chroot ${ROOTFS}
    update-grub
EOF
fi

if [ "$OSNAME" = "openmandriva" ]; then
echo openmandriva
lineinfile ${ROOTFS}/etc/default/grub ".*GRUB_TIMEOUT=.*" 'GRUB_TIMEOUT=0'
cat << EOF | chroot ${ROOTFS}
    if [ -d /sys/firmware/efi ]; then 
        sudo grub2-mkconfig -o /boot/efi/EFI/openmandriva/grub.cfg
    else 
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
EOF

fi

echo "fastboot activated"

}

disableturbo() {
# disable turbo boost

cat <<'EOF' | tee ${ROOTFS}/usr/local/bin/turboboost.sh
#!/bin/bash
input=$1
if [ "$input" = "no" ]; then
    state=1	
else
    state=0
fi
echo "no_turbo=$state"
if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
    echo $state > /sys/devices/system/cpu/intel_pstate/no_turbo
fi
EOF

chmod 755 ${ROOTFS}/usr/local/bin/turboboost.sh


cat <<EOF | tee ${ROOTFS}/etc/systemd/system/disable-intel-turboboost.service
[Unit]
Description=Disable Intel Turbo Boost using pstate driver 
[Service]
ExecStart=/bin/sh -c "/usr/local/bin/turboboost.sh no"
ExecStop=/bin/sh -c "/usr/local/bin/turboboost.sh yes"
RemainAfterExit=yes
[Install]
WantedBy=sysinit.target
EOF

cat << EOF | chroot ${ROOTFS}
    systemctl enable disable-intel-turboboost.service
EOF

}

firstbootexpandfs() {
# first boot script
cat <<EOF | tee ${ROOTFS}/usr/local/bin/firstboot.sh
#!/bin/bash
if [ ! -f /var/log/firstboot.log ]; then
    # Code to execute if log file does not exist
    echo "First boot script has run">/var/log/firstboot.log
    growpart /dev/sda 1
    resize2fs /dev/sda1
fi
EOF

chmod 755 ${ROOTFS}/usr/local/bin/firstboot.sh

cat <<EOF | tee ${ROOTFS}/etc/systemd/system/firstboot.service
[Unit]
Description=firstboot
Requires=network.target
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/firstboot.sh
RemainAfterExit=yes


[Install]
WantedBy=multi-user.target
EOF

cat << EOF | chroot ${ROOTFS}
    systemctl enable firstboot.service
EOF
echo "firstboot script activated"
}

bashaliases() {

if [ "$OSNAME" = "debian" ]; then
    export BASHRC="/etc/bash.bashrc"
fi

if [ "$OSNAME" = "openmandriva" ]; then
    export BASHRC="/etc/bashrc"
cat << EOF | chroot ${ROOTFS}
    ln -sf /usr/bin/vim /usr/bin/vi
EOF
fi

lineinfile ${ROOTFS}${BASHRC} ".*alias.*ll.*=.*" 'alias ll="ls -larth"'
lineinfile ${ROOTFS}${BASHRC} ".*alias.*ap=.*" 'alias ap=ansible-playbook'


lineinfile ${ROOTFS}${BASHRC} ".*export.*ROOTFS*=.*" 'export ROOTFS=\/'
lineinfile ${ROOTFS}${BASHRC} ".*export.*TARGET_USERNAME*=.*" "export TARGET_USERNAME=${TARGET_USERNAME}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*DOCKER_BUILDX_VERSION*=.*" "export DOCKER_BUILDX_VERSION=${DOCKER_BUILDX_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*MAJOR_KUBE_VERSION*=.*" "export MAJOR_KUBE_VERSION=${MAJOR_KUBE_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*K9S_VERSION*=.*" "export K9S_VERSION=${K9S_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*MVN_VERSION*=.*" "export MVN_VERSION=${MVN_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*NERDFONTS*=.*" "export NERDFONTS=${NERDFONTS}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*ZOOM_VERSION*=.*" "export ZOOM_VERSION=${ZOOM_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*MLVAPP_VERSION*=.*" "export MLVAPP_VERSION=${MLVAPP_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*BEEREF_VERSION*=.*" "export BEEREF_VERSION=${BEEREF_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*FREAC_VERSION*=.*" "export FREAC_VERSION=${FREAC_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*FREAC_VERSION*=.*" "export FREAC_VERSION=${FREAC_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*TEAMS_VERSION*=.*" "export TEAMS_VERSION=${TEAMS_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*CAPRINE_VERSION*=.*" "export CAPRINE_VERSION=${CAPRINE_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*DRAWIO_VERSION*=.*" "export DRAWIO_VERSION=${DRAWIO_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*CERTBOT_DUCKDNS_VERSION*=.*" "export CERTBOT_DUCKDNS_VERSION=${CERTBOT_DUCKDNS_VERSION}"
lineinfile ${ROOTFS}${BASHRC} ".*export.*OSNAME*=.*" "export OSNAME=${OSNAME}"

echo "bash aliases setup finished"
}

smalllogs() {

lineinfile ${ROOTFS}/etc/systemd/journald.conf ".*SystemMaxUse=.*" "SystemMaxUse=50M"

echo "lower log volume activated"

}

reposrc() {

if [ "$OSNAME" = "debian" ]; then
echo "setup apt"
cat <<EOF > ${ROOTFS}/etc/apt/sources.list
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

echo "apt sources setup finished"
fi

if [ "$OSNAME" = "openmandriva" ]; then
rm -f ${ROOTFS}/etc/yum.repos.d/*
curl -Lo ${ROOTFS}/etc/yum.repos.d/openmandriva-rolling-x86_64.repo https://raw.githubusercontent.com/alainpham/debian-os-image/refs/heads/master/om/openmandriva-rolling-x86_64.repo
fi

}

iessentials() {
# Essentials packages
echo "install essentials"

if [ "$OSNAME" = "debian" ]; then
cat << EOF | chroot ${ROOTFS}
    apt update && apt upgrade -y
    apt install -y sudo git tmux vim curl wget rsync ncdu dnsutils bmon systemd-timesyncd htop bash-completion gpg whois haveged zip unzip virt-what wireguard iptables jq
    DEBIAN_FRONTEND=noninteractive apt install -y cloud-guest-utils openssh-server console-setup iperf3
EOF
fi

if [ "$OSNAME" = "openmandriva" ]; then

cat << EOF | chroot ${ROOTFS}
    dnf clean -y all ; dnf -y repolist
    dnf -y --allowerasing distro-sync
    dnf install -y sudo git tmux vim curl wget rsync ncdu bind-utils htop bash-completion gnupg2 whois zip unzip virt-what wireguard-tools iptables jq
    dnf install -y cloud-utils openssh-server console-setup iperf
    dnf install -y ncurses-extraterms
EOF
fi

echo "essentials installed"

cat << EOF | chroot ${ROOTFS}
    git config --global core.editor "vim"
EOF

}

isudo() {
cat << EOF | chroot ${ROOTFS}
    echo '${TARGET_USERNAME} ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee' visudo -f /etc/sudoers.d/nopwd
EOF

echo "sudo setup finished"
}

allowsshpwd() {
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' ${ROOTFS}/etc/ssh/sshd_config
}

ikeyboard() {
# setup keyboard
cat <<EOF | tee ${ROOTFS}/etc/default/keyboard
# KEYBOARD CONFIGURATION FILE

# Consult the keyboard(5) manual page.

XKBMODEL="pc105"
XKBLAYOUT="${KEYBOARD_LAYOUT}"
# XKBVARIANT=""
# XKBOPTIONS=""

# BACKSPACE="guess"
EOF
echo "keyboard setup finished"

mkdir -p ${ROOTFS}/etc/X11/xorg.conf.d/

cat <<EOF | tee ${ROOTFS}/etc/X11/xorg.conf.d/30-touchpad.conf
Section "InputClass"
    Identifier "touchpad catchall"
    Driver "libinput"
    Option "Tapping" "on"
EndSection
EOF

}

idocker() {

echo "install docker"

if [ "$OSNAME" = "debian" ]; then
cat << EOF | chroot ${ROOTFS}
    apt install -y docker.io python3-docker docker-compose skopeo
    apt install -y ansible openjdk-17-jdk-headless npm golang-go
EOF

cat <<EOF | tee ${ROOTFS}/etc/docker/daemon.json
{
  "log-opts": {
    "max-size": "10m",
    "max-file": "2" 
  }
}
EOF
echo "docker logs configured"

cat << EOF | chroot ${ROOTFS}
    adduser $TARGET_USERNAME docker
EOF

export JAVA_HOME_TARGET=/usr/lib/jvm/java-17-openjdk-amd64
lineinfile ${ROOTFS}/etc/bash.bashrc ".*export.*JAVA_HOME*=.*" "export JAVA_HOME=${JAVA_HOME_TARGET}"

echo "java home setup finished"
fi

if [ "$OSNAME" = "openmandriva" ]; then

cat << EOF | chroot ${ROOTFS}
    dnf install -y docker python-docker docker-compose skopeo
    dnf install -y ansible java-17-openjdk-devel npm golang
    systemctl enable docker
EOF

cat <<EOF | tee ${ROOTFS}/etc/docker/daemon.json
{
  "iptables": true
}
EOF
echo "docker logs configured"

cat << EOF | chroot ${ROOTFS}
    usermod -aG docker $TARGET_USERNAME
EOF

export JAVA_HOME_TARGET=/usr/lib/jvm/java-17-openjdk
lineinfile ${ROOTFS}/etc/bashrc ".*export.*JAVA_HOME*=.*" "export JAVA_HOME=${JAVA_HOME_TARGET}"
lineinfile ${ROOTFS}/etc/bashrc ".*export.*PATH*=.*" "export PATH=\$PATH:${JAVA_HOME_TARGET}/bin"

fi





mkdir -p ${ROOTFS}/usr/lib/docker/cli-plugins
curl -SL https://github.com/docker/buildx/releases/download/${DOCKER_BUILDX_VERSION}/buildx-${DOCKER_BUILDX_VERSION}.linux-amd64 -o ${ROOTFS}/usr/lib/docker/cli-plugins/docker-buildx
chmod 755 ${ROOTFS}/usr/lib/docker/cli-plugins/docker-buildx

echo "docker build x installed"

# cat << EOF | chroot ${ROOTFS}
#     echo "export JAVA_HOME=${JAVA_HOME_TARGET}" | tee /etc/profile.d/java_home.sh
# EOF
# install maven

mkdir -p ${ROOTFS}/opt/appimages/
curl -L -o /tmp/maven.tar.gz https://dlcdn.apache.org/maven/maven-3/${MVN_VERSION}/binaries/apache-maven-${MVN_VERSION}-bin.tar.gz
tar xzvf /tmp/maven.tar.gz  -C ${ROOTFS}/opt/appimages/
cat << EOF | chroot ${ROOTFS}
    ln -sf /opt/appimages/apache-maven-${MVN_VERSION}/bin/mvn /usr/local/bin/mvn
EOF
rm -f /tmp/maven.tar.gz
echo "maven installed"

cat <<EOF | tee ${ROOTFS}/usr/local/bin/firstboot-dockernet.sh
#!/bin/bash
echo "Setting up dedicated network bridge.."
if [[ -z "\$(docker network ls | grep primenet)" ]] then
     docker network create --driver=bridge --subnet=172.18.0.0/16 --gateway=172.18.0.1 primenet
     echo "net created"
     echo "✅ primenet docker network created !">/var/log/firstboot-dockernet.log
else
     echo "net exists"
     echo "✅ primenet already exisits ! ">/var/log/firstboot-dockernet.log
fi
EOF

cat <<EOF | tee ${ROOTFS}/usr/local/bin/firstboot-dockerbuildx.sh
#!/bin/bash

echo "Setting up builder"
if [[ -z "\$(docker buildx ls | grep multibuilder.*linux)" ]] then
     docker buildx create --name multibuilder --platform linux/amd64,linux/arm/v7,linux/arm64/v8 --use
     echo "✅ multibuilder docker buildx created !">/var/log/firstboot-dockerbuildx.log
else
     echo "build exists"
     echo "✅ multibuilder already exisits ! ">~/firstboot-dockerbuildx.log
fi
EOF

chmod 755 ${ROOTFS}/usr/local/bin/firstboot-dockernet.sh
chmod 755 ${ROOTFS}/usr/local/bin/firstboot-dockerbuildx.sh

cat <<EOF | tee ${ROOTFS}/etc/systemd/system/firstboot-dockernet.service
[Unit]
Description=firstboot-dockernet
Requires=network.target docker.service
After=network.target docker.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/firstboot-dockernet.sh
RemainAfterExit=yes


[Install]
WantedBy=multi-user.target
EOF

cat <<EOF | tee ${ROOTFS}/etc/systemd/system/firstboot-dockerbuildx.service
[Unit]
Description=firstboot-dockerbuildx
Requires=network.target docker.service
After=network.target docker.service

[Service]
Type=oneshot
User=${TARGET_USERNAME}
ExecStart=/usr/local/bin/firstboot-dockerbuildx.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat << EOF | chroot ${ROOTFS}
    systemctl enable firstboot-dockernet.service
    systemctl enable firstboot-dockerbuildx.service
EOF
echo "docker network and buildx on first boot service configured"

}

ikubectl(){
echo "install kubectl"

if [ "$OSNAME" = "debian" ]; then
cat << EOF | chroot ${ROOTFS}
    curl -fsSL https://pkgs.k8s.io/core:/stable:/$MAJOR_KUBE_VERSION/deb/Release.key | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$MAJOR_KUBE_VERSION/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

    apt update
    apt install -y kubectl
EOF

echo "install helm"
cat << EOF | chroot ${ROOTFS}
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
    apt update
    apt install helm -y
EOF
fi

if [ "$OSNAME" = "openmandriva" ]; then

cat <<EOF | tee ${ROOTFS}/etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${MAJOR_KUBE_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${MAJOR_KUBE_VERSION}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF


cat << EOF | chroot ${ROOTFS}
    dnf install -y kubectl --disableexcludes=kubernetes
EOF

cat << EOF | chroot ${ROOTFS}
    curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 755 /tmp/get_helm.sh
    /tmp/get_helm.sh
EOF


fi

cat << EOF | chroot ${ROOTFS}
    kubectl completion bash | tee /etc/bash_completion.d/kubectl > /dev/null
    helm completion bash | tee /etc/bash_completion.d/helm > /dev/null
EOF

cat << EOF | chroot ${ROOTFS}
    curl -LO https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz
    tar -xzvf k9s_Linux_amd64.tar.gz  -C /usr/local/bin/ k9s
    chown root:root /usr/local/bin/k9s
    rm k9s_Linux_amd64.tar.gz
EOF



}

ikube() {
 
echo "install kube readiness"

cat <<EOF | tee ${ROOTFS}/etc/modules-load.d/containerd.conf 
overlay 
br_netfilter
EOF

cat <<EOF | tee ${ROOTFS}/etc/sysctl.d/99-kubernetes-k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1 
net.bridge.bridge-nf-call-ip6tables = 1 
EOF
echo "kube readiness setup finished"

if [ "$OSNAME" = "debian" ]; then
cat << EOF | chroot ${ROOTFS}
    apt install -y containerd
EOF
fi

if [ "$OSNAME" = "openmandriva" ]; then
cat << EOF | chroot ${ROOTFS}
    dnf install -y containerd
EOF
fi

echo "containerd setup"

cat << EOF | chroot ${ROOTFS}
    mkdir -p /etc/containerd
    containerd config default | tee /etc/containerd/config.toml >/dev/null 2>&1
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
EOF

ikubectl

echo "install kube server"

if [ "$OSNAME" = "debian" ]; then
cat << EOF | chroot ${ROOTFS}
    apt install -y kubelet kubeadm
EOF
fi

if [ "$OSNAME" = "openmandriva" ]; then
cat << EOF | chroot ${ROOTFS}
    dnf install -y kubelet kubeadm --disableexcludes=kubernetes
    systemctl enable kubelet
    systemctl enable containerd
EOF
fi

}

idlkubeimg() {
echo "download kube images"
cat << EOF | chroot ${ROOTFS}
    kubeadm config images pull
EOF
}

invidia() {

echo "install nvidia drivers"

cat << EOF | chroot ${ROOTFS}
    apt install -y nvidia-detect
EOF

export NV_VERSION=$(echo "nvidia-detect  | grep nvidia.*driver | xargs" | chroot ${ROOTFS})

cat << EOF | chroot ${ROOTFS}
    apt install -y $NV_VERSION
EOF

# avoid screen tearing

cat << 'EOF' >> ${ROOTFS}/etc/X11/xorg.conf.d/20-intel.conf
Section "Device"
  Identifier "Intel Graphics"
  Driver "modesetting"
EndSection
EOF

mkdir -p ${ROOTFS}/home/$TARGET_USERNAME/.config/picom/
cat << 'EOF' >> ${ROOTFS}/home/$TARGET_USERNAME/.config/picom/picom.conf
backend = "glx";
vsync = true;
use-damage = false
EOF

chown -R $TARGET_USERNAME:$TARGET_USERNAME ${ROOTFS}/home/$TARGET_USERNAME/.config

echo 'GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX nvidia-drm.modeset=1"' > ${ROOTFS}/etc/default/grub.d/nvidia-modeset.cfg

cat << EOF | chroot ${ROOTFS}
    update-grub
EOF

cat << EOF | chroot ${ROOTFS}
    systemctl enable nvidia-suspend.service
    systemctl enable nvidia-hibernate.service
    systemctl enable nvidia-resume.service
EOF
echo 'options nvidia NVreg_PreserveVideoMemoryAllocations=1' > ${ROOTFS}/etc/modprobe.d/nvidia-power-management.conf
}

igui() {

echo "install gui"
# if pulse replace by this apt install -y pulseaudio
    # apt install -y  pipewire-audio wireplumber pipewire-pulse pipewire-alsa libspa-0.2-bluetooth pulseaudio-utils qpwgraph pavucontrol

cat << EOF | chroot ${ROOTFS}
    apt install -y make gcc libx11-dev libxft-dev libxrandr-dev libimlib2-dev libfreetype-dev libxinerama-dev xorg numlockx 
    apt install -y pulseaudio pulseaudio-module-bluetooth pulseaudio-utils pavucontrol alsa-utils
    apt remove -y xserver-xorg-video-intel
EOF

echo "install nerdfonts"
for font in ${NERDFONTS} ; do
 echo "installing $font"
 wget -O ${ROOTFS}/tmp/${font}.zip "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${font}.zip"
 mkdir -p ${ROOTFS}/usr/share/fonts/nerd-fonts/
 unzip -o /tmp/${font}.zip -d ${ROOTFS}/usr/share/fonts/nerd-fonts/
 rm /tmp/${font}.zip
 echo "installed $font"
done
 
echo "additional gui packages"
cat << EOF | chroot ${ROOTFS}
    apt install -y ntfs-3g ifuse mpv haruna vlc cmatrix nmon mesa-utils neofetch feh network-manager dnsmasq acpitool lm-sensors fonts-noto libnotify-bin dunst ffmpeg python3-mutagen imagemagick mediainfo-gui arandr picom brightnessctl cups xsane libsane sane-utils filezilla speedcrunch fonts-font-awesome lxappearance breeze-gtk-theme 
EOF

cat << EOF | chroot ${ROOTFS}
    systemctl disable dnsmasq
EOF

cat << 'EOF' | tee ${ROOTFS}/etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback
EOF

cat << 'EOF' | tee ${ROOTFS}/etc/NetworkManager/conf.d/00-use-dnsmasq.conf
[main]
dns=dnsmasq
EOF

cat << 'EOF' | tee ${ROOTFS}/etc/NetworkManager/dnsmasq.d/dev.conf
#/etc/NetworkManager/dnsmasq.d/dev.conf
local=/zez.duckdns.org/
address=/zez.duckdns.org/127.0.0.1
EOF

# dunst notification
mkdir -p ${ROOTFS}/home/$TARGET_USERNAME/.config/dunst
cat << 'EOF' | tee ${ROOTFS}/home/$TARGET_USERNAME/.config/dunst/dunstrc
[global]
monitor = 2
# follow = keyboard
font = Noto Sans 11
frame_width = 2
frame_color = "#4e9a06"
offset = 20x65
[urgency_low]
    background = "#4e9a06"
    foreground = "#eeeeec"
[urgency_normal]
    background = "#2e3436"
    foreground = "#eeeeec"
[urgency_critical]
    background = "#a40000"
    foreground = "#eeeeec"
EOF

cat << EOF | chroot ${ROOTFS}
    chown -R $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/.config/dunst
EOF



#YT-DLP latest
curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o ${ROOTFS}/usr/local/bin/yt-dlp
cat << EOF | chroot ${ROOTFS}
    chmod 755 /usr/local/bin/yt-dlp
EOF

# ffmpeg scripts
ffmpegscripts="vconv-archive-lossless-h264-vaapi.sh vconv-extract-audio.sh vconv-h264-vaapi-qp.sh vconv-h264-vaapi-vbr.sh vconv-hevc-vaapi-qp.sh vconv-make-mkv.sh vconv-make-mp4.sh vconv-mp3-hq.sh vconv-ripcapt.sh vconv-ripscreen.sh vconv-vp9-vaapi-qp.sh vconv-x264-crf.sh vconv-x264-lowres-lowvbr-2pass.sh vconv-x264-lowres-vbr-2pass.sh vconv-x264-vbr-2pass.sh"
for script in $ffmpegscripts ; do
curl -Lo ${ROOTFS}/usr/local/bin/$script https://raw.githubusercontent.com/alainpham/debian-os-image/master/scripts/ffmpeg/$script
cat << EOF | chroot ${ROOTFS}
    chmod 755 /usr/local/bin/$script
EOF
done

# pulseaudio podcast setup

# asoundrc
cat << 'EOF' | tee ${ROOTFS}/home/$TARGET_USERNAME/.asoundrc
pcm.pulse {
    type pulse
}

ctl.pulse {
    type pulse
}
EOF

# create alsa loopback
lineinfile ${ROOTFS}/etc/modules ".*snd-aloop.*" "snd-aloop"
lineinfile ${ROOTFS}/etc/modules ".*snd-dummy.*" "snd-dummy"

cat << 'EOF' | tee ${ROOTFS}/etc/modprobe.d/alsa-loopback.conf
options snd-aloop index=10 id=loop
options snd-dummy index=11 id=dummy
EOF

# avoid crackling with pulse
lineinfile ${ROOTFS}/etc/pulse/default.pa ".*load-module module-suspend-on-idle.*" "load-module module-suspend-on-idle"
lineinfile ${ROOTFS}/etc/pulse/system.pa ".*load-module module-suspend-on-idle.*" "load-module module-suspend-on-idle"

wget -O ${ROOTFS}/etc/pulse/default.pa.d/pulsepod.pa https://raw.githubusercontent.com/alainpham/debian-os-image/master/scripts/pulseaudio/pulsepod.pa

lineinfile ${ROOTFS}/etc/pulse/daemon.conf ".*default-sample-rate.*" "default-sample-rate = 48000"
lineinfile ${ROOTFS}/etc/pulse/daemon.conf ".*default-sample-format.*" "default-sample-format = s16le"
# lineinfile ${ROOTFS}/etc/pulse/daemon.conf ".*default-fragment-size-msec.*" "default-fragment-size-msec = 40"
# lineinfile ${ROOTFS}/etc/pulse/daemon.conf ".*default-fragments.*" "default-fragments = 4"
lineinfile ${ROOTFS}/etc/pulse/daemon.conf ".*resample-method.*" "resample-method = soxr-hq"

# install scripts
gitroot=https://raw.githubusercontent.com/alainpham/debian-os-image/refs/heads/master/scripts/pulseaudio/
files="snd asnd asndenv asnddef csndfoczv csndzv csndh6 csndint clrmix clrmixoff"
for file in $files ; do
curl -Lo ${ROOTFS}/usr/local/bin/$file $gitroot/$file
chmod 755 ${ROOTFS}/usr/local/bin/$file
done





# wireplumber and pipewire
curl -Lo ${ROOTFS}/etc/udev/rules.d/89-pulseaudio-udev.rules https://raw.githubusercontent.com/alainpham/debian-os-image/refs/heads/master/scripts/pulseaudio/89-pulseaudio-udev.rules

# cat << EOF | chroot ${ROOTFS}
# cp -R /usr/share/pipewire /home/${TARGET_USERNAME}/.config/
# cp -R /usr/share/wireplumber /home/${TARGET_USERNAME}/.config/

# mkdir -p /home/${TARGET_USERNAME}/.config/pipewire/pipewire.conf.d/
# curl -Lo /home/$TARGET_USERNAME/.config/pipewire/pipewire.conf.d/podcast.conf https://raw.githubusercontent.com/alainpham/debian-os-image/refs/heads/master/scripts/pulseaudio/podcast.conf
# curl -Lo /home/$TARGET_USERNAME/.config/pipewire/pipewire-pulse.conf https://raw.githubusercontent.com/alainpham/debian-os-image/refs/heads/master/scripts/pulseaudio/pipewire-pulse.conf

# chown -R $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/.config/pipewire
# chown -R $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/.config/wireplumber
# EOF

# install scripts for webcam
gitroot=https://raw.githubusercontent.com/alainpham/debian-os-image/refs/heads/master/scripts/camera/
files="cint c920"
for file in $files ; do
curl -Lo ${ROOTFS}/usr/local/bin/$file $gitroot/$file
chmod 755 ${ROOTFS}/usr/local/bin/$file
done

# install chrome browser
mkdir -p ${ROOTFS}/opt/debs/
wget -O /opt/debs/google-chrome-stable_current_amd64.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb 
cat << EOF | chroot ${ROOTFS}
    apt install -y /opt/debs/google-chrome-stable_current_amd64.deb
EOF

#begin dwm
if [ ! -d ${ROOTFS}/home/$TARGET_USERNAME/wm ] ; then

echo "The does not exist, installing dwm"
cat << EOF | chroot ${ROOTFS}
    mkdir -p /home/$TARGET_USERNAME/wm
    cd /home/$TARGET_USERNAME/wm
    git clone https://github.com/alainpham/dwm-flexipatch.git
    git clone https://github.com/alainpham/st-flexipatch.git
    git clone https://github.com/alainpham/dmenu-flexipatch.git
    git clone https://github.com/alainpham/dwmblocks.git
    git clone https://github.com/alainpham/slock-flexipatch.git

    cd /home/$TARGET_USERNAME/wm/dwm-flexipatch && make clean install
    cd /home/$TARGET_USERNAME/wm/st-flexipatch && make clean install
    cd /home/$TARGET_USERNAME/wm/dmenu-flexipatch && make clean install
    cd /home/$TARGET_USERNAME/wm/dwmblocks && make clean install
    cd /home/$TARGET_USERNAME/wm/slock-flexipatch && make clean install

    chown -R $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/wm
EOF
# end dwm
fi 

# wallpaper
mkdir -p ${ROOTFS}/usr/share/backgrounds/
wget -O ${ROOTFS}/usr/share/backgrounds/01.jpg https://free-images.com/or/8606/canyon_antelope_canyon_usa_1.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/02.jpg https://free-images.com/or/9cf1/city_overcast_buildings_skyline.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/03.jpg https://free-images.com/lg/f1b3/sunset_on_seine.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/04.jpg https://free-images.com/lg/e216/parrots_macaw_bird_parrot.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/05.jpg https://free-images.com/lg/ac18/city_night_light_bokeh.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/06.jpg https://free-images.com/lg/5cc4/lights_night_city_night.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/07.jpg https://free-images.com/lg/64e0/heavens_peek.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/08.jpg https://free-images.com/lg/5d7d/painting_watercolor_wax_stains.jpg
wget -O ${ROOTFS}/usr/share/backgrounds/09.jpg https://raw.githubusercontent.com/simple-sunrise/Light-and-Dark-Wallpapers-for-Gnome/main/Wallpapers/LakesideDeer/LakesideDeer-1.png
wget -O ${ROOTFS}/usr/share/backgrounds/10.jpg https://raw.githubusercontent.com/simple-sunrise/Light-and-Dark-Wallpapers-for-Gnome/main/Wallpapers/LakesideDeer/LakesideDeer-2.png

cat << EOF | tee ${ROOTFS}/home/$TARGET_USERNAME/.xsession
#!/bin/sh

setxkbmap ${KEYBOARD_LAYOUT}
EOF

cat << 'EOF' >> ${ROOTFS}/home/$TARGET_USERNAME/.xsession
numlockx
echo 0 | tee ~/.rebootdwm
export rebootdwm=$(cat ~/.rebootdwm)
while true; do
    piddwmblocks=$(pgrep dwmblocks)
    if [ -z "$piddwmblocks" ]; then
        dwmblocks &
    else
        kill -9 $piddwmblocks
        dwmblocks &
    fi
    bgfile=$(ls /usr/share/backgrounds/ | shuf -n 1)
    feh --bg-fill /usr/share/backgrounds/${bgfile}
    picom -b --config ~/.config/picom/picom.conf
    # Log stderror to a file
    dwm 2> ~/.dwm.log
    # No error logging
    #dwm >/dev/null 2>&1
    rebootdwm=$(cat ~/.rebootdwm)
    if [[ "$rebootdwm" = '0'  ]]; then
            break
    fi
done

EOF

cat << EOF | chroot ${ROOTFS}
    chown $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/.xsession
EOF

# picom initial config
if [ ! -f ${ROOTFS}/home/$TARGET_USERNAME/.config/picom/picom.conf ] ; then
mkdir -p ${ROOTFS}/home/$TARGET_USERNAME/.config/picom/
cat << 'EOF' >> ${ROOTFS}/home/$TARGET_USERNAME/.config/picom/picom.conf
# picom config
backend = "glx";
vsync = true;
use-damage = false
EOF
fi

# if inside virtual machine
# video=Virtual-1:1600x900

export hypervisor=$(echo "virt-what" | chroot ${ROOTFS})

# Hyperv
if [ "$hypervisor" = "hyperv" ]; then
sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/ {/video=Virtual-1:1600x900/! s/"$/ video=Virtual-1:1600x900"/}' ${ROOTFS}/etc/default/grub
cat << EOF | chroot ${ROOTFS}
    update-grub
EOF

cat <<EOF | tee ${ROOTFS}/etc/X11/xorg.conf.d/30-hyperv.conf
Section "Device"
  Identifier "HYPER_V Framebuffer"
  Driver "fbdev"
EndSection
EOF
#end hyperv
fi

}

iworkstation() {
echo "additional workstation tools"
cat << EOF | chroot ${ROOTFS}
    apt install -y handbrake gimp rawtherapee krita mypaint inkscape blender obs-studio mgba-qt v4l2loopback-utils kdenlive flameshot maim xclip xdotool thunar thunar-archive-plugin easytag audacity
EOF

mkdir -p ${ROOTFS}/home/workdrive/recordings
cat << EOF | chroot ${ROOTFS}
    chown -R $TARGET_USERNAME:$TARGET_USERNAME /home/workdrive
EOF

cat << 'EOF' | tee ${ROOTFS}/usr/local/bin/winshot.sh
maim -i $(xdotool getactivewindow) | xclip -selection clipboard -t image/png
EOF
cat << EOF | chroot ${ROOTFS}
    chmod 755 /usr/local/bin/winshot.sh
EOF

# configure Thunar
mkdir -p ${ROOTFS}/home/$TARGET_USERNAME/.config/Thunar/

cat << 'EOF' | tee ${ROOTFS}/home/$TARGET_USERNAME/.config/Thunar/uca.xml
<?xml version="1.0" encoding="UTF-8"?>
<actions>

<action>
        <icon>utilities-terminal</icon>
        <name>Open Terminal Here</name>
        <submenu></submenu>
        <unique-id>1727457442655389-1</unique-id>
        <command>st -d %f</command>
        <description>Open Terminal here</description>
        <range></range>
        <patterns>*</patterns>
        <startup-notify/>
        <directories/>
</action>
<action>
        <icon>utilities-terminal</icon>
        <name>VSCode</name>
        <submenu></submenu>
        <unique-id>1727457442655389-1</unique-id>
        <command>code %f</command>
        <description>Open VSCode here</description>
        <range></range>
        <patterns>*</patterns>
        <startup-notify/>
        <directories/>
</action>
</actions>
EOF

cat << EOF | chroot ${ROOTFS}
    chown -R $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/.config
EOF

cat << EOF | chroot ${ROOTFS}
    DEBIAN_FRONTEND=noninteractive apt install -y libdvd-pkg
EOF

echo "dpkg libdvd-pkg"
cat << EOF | chroot ${ROOTFS}
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg
EOF

# cat << EOF | chroot ${ROOTFS}
#     apt install -y snapd
#     snap install pinta
#     snap install rpi-imager
# EOF

#vscode
mkdir -p ${ROOTFS}/opt/debs/
wget -O ${ROOTFS}/opt/debs/vscode.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64"
cat << EOF | chroot ${ROOTFS}
    DEBIAN_FRONTEND=noninteractive apt install -y /opt/debs/vscode.deb
EOF


# install zoom
mkdir -p ${ROOTFS}/opt/debs/
wget -O ${ROOTFS}/opt/debs/zoom_amd64.deb https://zoom.us/client/${ZOOM_VERSION}/zoom_amd64.deb
cat << EOF | chroot ${ROOTFS}
    apt install -y /opt/debs/zoom_amd64.deb
EOF

mkdir -p ${ROOTFS}/opt/debs/
wget -O ${ROOTFS}/opt/debs/slack.deb https://downloads.slack-edge.com/desktop-releases/linux/x64/4.39.95/slack-desktop-4.39.95-amd64.deb
cat << EOF | chroot ${ROOTFS}
    apt install -y /opt/debs/slack.deb
EOF

# install onlyoffice
mkdir -p ${ROOTFS}/opt/debs/
wget -O /opt/debs/onlyoffice-desktopeditors_amd64.deb https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb
cat << EOF | chroot ${ROOTFS}
    apt install -y /opt/debs/onlyoffice-desktopeditors_amd64.deb
EOF

# install dbeaver
mkdir -p ${ROOTFS}/opt/debs/
wget -O ${ROOTFS}/opt/debs/dbeaver.deb https://dbeaver.io/files/dbeaver-ce_latest_amd64.deb
cat << EOF | chroot ${ROOTFS}
    apt install -y /opt/debs/dbeaver.deb
EOF

# APPimages
# MLVP APP
wget -O ${ROOTFS}/opt/appimages/mlvapp.AppImage https://github.com/ilia3101/MLV-App/releases/download/QTv${MLVAPP_VERSION}/MLV.App.v${MLVAPP_VERSION}.Linux.x86_64.AppImage
cat << EOF | chroot ${ROOTFS}
    chmod 755 /opt/appimages/mlvapp.AppImage
    ln -s /opt/appimages/mlvapp.AppImage /usr/local/bin/mlvapp
EOF

# Drawio
wget -O ${ROOTFS}/opt/appimages/drawio.AppImage https://github.com/jgraph/drawio-desktop/releases/download/v${DRAWIO_VERSION}/drawio-x86_64-${DRAWIO_VERSION}.AppImage
cat << EOF | chroot ${ROOTFS}
    chmod 755 /opt/appimages/drawio.AppImage
    ln -s /opt/appimages/drawio.AppImage /usr/local/bin/drawio
EOF


#viber
wget -O ${ROOTFS}/opt/appimages/viber.AppImage https://download.cdn.viber.com/desktop/Linux/viber.AppImage
cat << EOF | chroot ${ROOTFS}
    chmod 755 /opt/appimages/viber.AppImage
    ln -sf /opt/appimages/viber.AppImage /usr/local/bin/viber
EOF

# beeref
wget -O ${ROOTFS}/opt/appimages/beeref.AppImage https://github.com/rbreu/beeref/releases/download/v${BEEREF_VERSION}/BeeRef-${BEEREF_VERSION}.appimage
cat << EOF | chroot ${ROOTFS}
    chmod 755 /opt/appimages/beeref.AppImage
    ln -sf /opt/appimages/beeref.AppImage /usr/local/bin/beeref
EOF

#freac
wget -O ${ROOTFS}/opt/appimages/freac.AppImage https://github.com/enzo1982/freac/releases/download/v${FREAC_VERSION}/freac-${FREAC_VERSION}-linux-x86_64.AppImage
cat << EOF | chroot ${ROOTFS}
    chmod 755 /opt/appimages/freac.AppImage
    ln -sf /opt/appimages/freac.AppImage /usr/local/bin/freac
EOF

#teams
wget -O ${ROOTFS}/opt/appimages/teams-for-linux.AppImage https://github.com/IsmaelMartinez/teams-for-linux/releases/download/v${TEAMS_VERSION}/teams-for-linux-${TEAMS_VERSION}.AppImage
cat << EOF | chroot ${ROOTFS}
    chmod 755 /opt/appimages/teams-for-linux.AppImage
    ln -sf /opt/appimages/teams-for-linux.AppImage /usr/local/bin/teams-for-linux
EOF



#caprine facebook messenger
wget -O ${ROOTFS}/opt/appimages/caprine.AppImage https://github.com/sindresorhus/caprine/releases/download/v2.60.1/Caprine-2.60.1.AppImage
cat << EOF | chroot ${ROOTFS}
    chmod 755 /opt/appimages/caprine.AppImage
    ln -sf /opt/appimages/caprine.AppImage /usr/local/bin/caprine
EOF
#autostart apps
mkdir -p ${ROOTFS}/home/$TARGET_USERNAME/.local/share/dwm
cat << 'EOF' | tee ${ROOTFS}/home/$TARGET_USERNAME/.local/share/dwm/autostart.sh
slack &
asnddef &
EOF

cat << EOF | chroot ${ROOTFS}
    chown -R $TARGET_USERNAME:$TARGET_USERNAME /home/$TARGET_USERNAME/.local
EOF

}

ivirt(){
echo "virtualization tools"
cat << EOF | chroot ${ROOTFS}
    apt install -y qemu-system qemu-utils virtinst libvirt-clients libvirt-daemon-system libguestfs-tools bridge-utils libosinfo-bin virt-manager genisoimage
    adduser $TARGET_USERNAME libvirt
EOF



curl -Lo ${ROOTFS}/usr/local/bin/vmcr https://raw.githubusercontent.com/alainpham/debian-os-image/master/scripts/vms/vmcr
curl -Lo ${ROOTFS}/usr/local/bin/vmdl https://raw.githubusercontent.com/alainpham/debian-os-image/master/scripts/vms/vmdl
curl -Lo ${ROOTFS}/usr/local/bin/vmls https://raw.githubusercontent.com/alainpham/debian-os-image/master/scripts/vms/vmls
curl -Lo ${ROOTFS}/usr/local/bin/vmsh https://raw.githubusercontent.com/alainpham/debian-os-image/master/scripts/vms/vmsh

cat << EOF | chroot ${ROOTFS}
    chmod 755 /usr/local/bin/vmcr /usr/local/bin/vmdl /usr/local/bin/vmls /usr/local/bin/vmsh

    if [ ! -f /home/${TARGET_USERNAME}/.ssh/vm ]; then
        ssh-keygen -f /home/${TARGET_USERNAME}/.ssh/vm -N ""
    fi

    chown -R ${TARGET_USERNAME}:${TARGET_USERNAME} /home/${TARGET_USERNAME}/.ssh/vm*
    
    mkdir -p /home/workdrive/virt/images
    mkdir -p /home/workdrive/virt/runtime
    chown -R ${TARGET_USERNAME}:${TARGET_USERNAME} /home/workdrive
EOF

# first boot script
cat <<EOF | tee ${ROOTFS}/usr/local/bin/firstboot-virt.sh
#!/bin/bash
echo "Setting up network for virtualization.."
if [[ -z "\$(virsh net-list | grep default)" ]] then
     virsh net-autostart default
     virsh net-start default
     echo "net autostart activated"
     echo "default net autostart activated !">/var/log/firstboot-virt.log
else
     echo "net exists"
     echo "default already autostarted ! ">/var/log/firstboot-virt.log
fi
EOF

chmod 755 ${ROOTFS}/usr/local/bin/firstboot-virt.sh

cat <<EOF | tee ${ROOTFS}/etc/systemd/system/firstboot-virt.service
[Unit]
Description=firstboot-virt
Requires=network.target libvirtd.service
After=network.target libvirtd.service

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/firstboot-virt.sh
RemainAfterExit=yes


[Install]
WantedBy=multi-user.target
EOF

cat << EOF | chroot ${ROOTFS}
    systemctl enable firstboot-virt.service
EOF
}

cleanupapt() {
echo "cleaning up"
cat << EOF | chroot ${ROOTFS}
    apt-get clean && rm -rf /var/lib/apt/lists/*
EOF
}

unmountraw() {
echo "Unmounting filesystems"
umount ${ROOTFS}/{dev/pts,boot/efi,dev,run,proc,sys,tmp,}

losetup -D

}

init() {
    # Set the default values
    inputversions
    inputkeyboard
    inputtasks $@
}

# Model to run all the script
all(){

if ! [ $# -eq 7 ]; then

    echo "make sure to download debian cloud image : rm debian-12-nocloud-amd64.raw && wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.raw"

    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME> <3_TARGET_PASSWD> <4_AUTHSSHFILE> <5_INPUT_IMG> <6_OUTPUT_IMAGE> <7_DISK_SIZE>"
    echo "cloud fullgui:        sudo $0 all apham ps authorized_keys debian-12-nocloud-amd64.raw d12-fgui.raw 5G"
    echo "cloud full:           sudo $0 all apham ps authorized_keys debian-12-nocloud-amd64.raw d12-full.raw 5G"
    echo "cloud image min:      sudo $0 all apham ps authorized_keys debian-12-nocloud-amd64.raw d12-mini.raw 3G"
    echo "cloud image kube:     sudo $0 all apham ps authorized_keys debian-12-nocloud-amd64.raw d12-kube.raw 4G"

    return
fi

init $@
mountraw
createuser
setpasswd
authkeys
rmnouveau
fastboot
disableturbo
firstbootexpandfs
bashaliases
smalllogs
reposrc
iessentials
isudo
allowsshpwd
ikeyboard
idocker
ikube
idlkubeimg
invidia
igui
iworkstation
ivirt
cleanupapt
unmountraw
sudo reboot now
}

# baremetal workstation with virtualization and without nvidia cards
wkstatvrt(){
if ! [ $# -eq 2 ]; then
    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME>"
    echo "sudo $0 wkstatvrt apham"
    return
fi

init $1 $2 "ps" "authorized_keys" "NA" "NA" "NA"
rmnouveau
fastboot
disableturbo
bashaliases
smalllogs
reposrc
iessentials
isudo
allowsshpwd
# ikeyboard
idocker
ikube
igui
iworkstation
ivirt
sudo reboot now
}

# baremetal workstation without virtualization & nvidia
wkstation(){
if ! [ $# -eq 2 ]; then
    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME>"
    echo "sudo $0 wkstation apham"
    return
fi
init $1 $2 "ps" "authorized_keys" "NA" "NA" "NA"
rmnouveau
fastboot
disableturbo
bashaliases
smalllogs
reposrc
iessentials
isudo
allowsshpwd
# ikeyboard
idocker
ikube
igui
iworkstation
sudo reboot now
}

#full gui server
fullgui(){
if ! [ $# -eq 2 ]; then
    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME>"
    echo "sudo $0 fullgui apham"
    return
fi
init $1 $2 "ps" "authorized_keys" "NA" "NA" "NA"
rmnouveau
fastboot
disableturbo
bashaliases
smalllogs
reposrc
iessentials
isudo
allowsshpwd
ikeyboard
idocker
ikube
igui
sudo reboot now
}

# for cloud servers like on oci, aws, gcp

debianserver(){
if ! [ $# -eq 2 ]; then
    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME>"
    echo "sudo $0 debianserver apham"
    return
fi
init $1 $2 "ps" "authorized_keys" "NA" "NA" "NA"
createuser
authkeys
bashaliases
smalllogs
reposrc
iessentials
isudo
idocker
ikube
sudo reboot now
}


ubuntuserver(){
if ! [ $# -eq 2 ]; then
    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME>"
    echo "sudo $0 ubuntuserver apham"
    return
fi
init $1 $2 "ps" "authorized_keys" "NA" "NA" "NA"
createuser
authkeys
bashaliases
smalllogs
iessentials
isudo
idocker
ikube
sudo reboot now
}

gcpvm(){
if ! [ $# -eq 2 ]; then
    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME>"
    echo "sudo $0 debianserver apham"
    return
fi
init $1 $2 "ps" "authorized_keys" "NA" "NA" "NA"
bashaliases
smalllogs
iessentials
idocker
ikubectl
sudo reboot now
}

gcpkube(){
if ! [ $# -eq 2 ]; then
    echo "Usage: sudo $0 <1_OPERATION> <2_TARGET_USERNAME>"
    echo "sudo $0 debianserver apham"
    return
fi
init $1 $2 "ps" "authorized_keys" "NA" "NA" "NA"
bashaliases
smalllogs
iessentials
idocker
ikube
sudo reboot now
}

runtest(){
init runtest apham "NA" "authorized_keys" "NA" "NA" "NA"
rmnouveau
fastboot
disableturbo
bashaliases
smalllogs
reposrc
iessentials
isudo
allowsshpwd
idocker
}