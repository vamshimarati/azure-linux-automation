#!/bin/bash

CONSTANTS_FILE="./constants.sh"
ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occurred during the test

#######################################################################
#
# UpdateTestState()
#
#######################################################################

UpdateTestState()
{
    echo "${1}" > ./state.txt
}

#######################################################################
#
# ResetLogFiles()
#
#######################################################################

ResetLogFiles()
{
    echo "" > ~/flent_config.log
    echo "" > ~/summary.log
}

#######################################################################
#
# LogMsg()
#
#######################################################################

LogMsg()
{
    echo `date "+%b %d %Y %T"` : "${1}"  >> ~/flent_config.log  # Add the time stamp to the log message
}

#######################################################################
#
# UpdateSummary()
#
#######################################################################
UpdateSummary()
{
    echo "${1}" >> ~/summary.log
    if [ $1 == "ABORTED" ]; then
        exit -1
    fi
}

#######################################################################
#
# get_host_version()
#
#######################################################################

function get_host_version ()
{
    if [ x$1 == "x" ]; then
        Server_version=`dmesg | grep "Host Build" | sed "s/.*Host Build://"|sed "s/^.*-\([0-9]*\.[0-9]*\)-.*/\1 /"`
    else
        Server_version=$1
    fi

    if [ x$Server_version != "x" ]; then
        if [ $Server_version == "6.2" ];then
            echo "WS2012"
        elif [ $Server_version == "6.3" ];then
            echo "WS2012R2"
        elif [ $Server_version == "10.0" ];then
            echo "WS2016"
        else
            echo "Unknown host OS version: $Server_version"
        fi
    else
        LogMsg "Unable to ditect host OS version"
    fi
}

#######################################################################
#
# check_exit_status()
#
#######################################################################

function check_exit_status ()
{
    exit_status=$?
    message=$1

    if [ $exit_status -ne 0 ]; then
        LogMsg "$message : Failed (exit code: $exit_status)"
        if [ "$2" == "exit" ]
        then
            UpdateSummary "ABORTED"
            exit $exit_status
        fi
    else
        LogMsg "$message : Success"
    fi
}

#######################################################################
#
# detect_linux_distribution_version()
#
#######################################################################

function detect_linux_distribution_version()
{
    local  distro_version="Unknown"
    if [ `which lsb_release 2>/dev/null` ]; then
        distro_version=`lsb_release -a  2>/dev/null | grep Release| sed "s/.*:\s*//"`
    else
        local temp_text=`cat /etc/*release*`
        distro_version=`cat /etc/*release*| grep -i release| sed "s/^.*release \([0-9]*\)\.\([0-9]*\).*(.*/\1\.\2/" | head -1` && `cat /etc/*release* | grep -i "version=" | cut -d "=" -f2 | awk {'print $1'} | sed -e 's/"//g'`
    fi

    echo $distro_version
}

#######################################################################
#
# detect_distribution()
#
#######################################################################

function detect_distribution()
{
    local linux_distribution_type='UNKNOWN'
    if [ `which lsb_release 2>/dev/null` ]; then
        if [ `lsb_release -a 2>/dev/null| grep "Distributor ID:"| grep -i Ubuntu | wc -l` -eq 1 ]; then
            linux_distribution_type="Ubuntu"
        elif [ `lsb_release -a 2>/dev/null| grep "Distributor ID:"| grep -i redhat | wc -l` -eq 1 ]; then
            linux_distribution_type="RHEL"
        elif [ `lsb_release -a 2>/dev/null| grep "Distributor ID:"| grep -i CentOS | wc -l` -eq 1 ]; then
            linux_distribution_type="CentOS"
        fi
    else
        local temp_text=`cat /etc/*release*|grep "^ID="`

        if echo "$temp_text" | grep -qi "ol"; then
            linux_distribution_type='Oracle'
        elif echo "$temp_text" | grep -qi "Ubuntu"; then
            linux_distribution_type='Ubuntu'
        elif echo "$temp_text" | grep -qi "sles"; then
            linux_distribution_type='SLES'
        elif echo "$temp_text" | grep -qi "openSUSE"; then
            linux_distribution_type='OpenSUSE'
        elif [ `echo "$temp_text" | grep -i "centos"|wc -l` -gt 0 ] ; then
            linux_distribution_type='CentOS'
        elif echo "$temp_text" | grep -qi "Oracle"; then
            linux_distribution_type='Oracle'
        elif echo $temp_text | grep -qi "rhel"; then
            linux_distribution_type='RHEL'
        else
            linux_distribution_type='unknown'
        fi
    fi

    echo $linux_distribution_type
}

#######################################################################
#
# updaterepos()
#
#######################################################################

function updaterepos()
{
   if [ `which yum 2>/dev/null` ]; then
        yum makecache
    elif [ `which apt-get 2>/dev/null` ]; then
        apt-get update
    elif [ `which zypper 2>/dev/null` ]; then
        zypper refresh
    fi
}

#######################################################################
#
# install_rpm()
#
#######################################################################

function install_rpm ()
{
    package_name=$1
    rpm -ivh $package_name
    check_exit_status "install_rpm $package_name"
}
#######################################################################
#
# install_deb()
#
#######################################################################

function install_deb ()
{
    package_name=$1
    dpkg -i  $package_name
    apt-get install -f
    check_exit_status "install_deb $package_name"
}

#######################################################################
#
# apt_get_install()
#
#######################################################################

function apt_get_install ()
{
    package_name=$1
    DEBIAN_FRONTEND=noninteractive apt-get install -y  --force-yes $package_name
    check_exit_status "apt_get_install $package_name"
}

#######################################################################
#
# yum_install()
#
#######################################################################

function yum_install ()
{
  IFS=' ' read -r -a packages_array < "$@"
  for index in  "${!packages_array[@]}"
  do
    package_name=${packages_array[index]}
    rpm -q $package_name > /dev/null
      if [ $? == 0 ] ;then
          LogMsg "'$package_name' is already installed, skipping installation.."
      else
          yum install -y $package_name >> ~/flent_config.log
          check_exit_status "yum_install: Installation of '$package_name'" "exit"
      fi
  done
}

#######################################################################
#
# zypper_install()
#
#######################################################################

function zypper_install ()
{
    package_name=$1
    zypper --non-interactive in $package_name
    check_exit_status "zypper_install $package_name"
}

#######################################################################
#
# install_package()
#
#######################################################################

function install_package ()
{
    local package_name=$@

    if [ `which yum` ]; then
        yum_install "$package_name"
    elif [ `which apt-get` ]; then
        apt_get_install "$package_name"
    elif [ `which zypper` ]; then
        zypper_install "$package_name"
    fi
}

#######################################################################
#
# config_flent_RHEL()
#
#######################################################################

function config_flent_RHEL
{
    local distro_version=`detect_linux_distribution_version`
    local distribution=`detect_distribution`
    
	if [ x$host_version == "x" ]; then
        host_version=`dmesg | grep "Host Build" | sed "s/.*Host Build://"|sed "s/^.*-\([0-9]*\.[0-9]*\)-.*/\1 /"`
        if [ x$host_version == "x" ]; then
            LogMsg "Unable to find Host version"
            UpdateSummary "ABORTED"
        fi
    fi
    LogMsg "Downloading required packages for FLENT on client VM ${client} and server VM ${server}"
	wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/assmannst/RHEL_5/x86_64/netperf-2.6.0-9.1.x86_64.rpm
	wget https://bootstrap.pypa.io/get-pip.py
	ssh root@${server} "wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/assmannst/RHEL_5/x86_64/netperf-2.6.0-9.1.x86_64.rpm"
	check_exit_status "Successfully downloaded required packages for FLENT on client VM ${client} and server VM ${server}"
	UpdateSummary "Downloaded required packages for FLENT-TEST on both client VM ${client} and server VM ${server}"
	LogMsg "Installing packages for FLENT on client VM ${client} and server VM ${server}"
	rpm -ivh netperf-2.6.0-9.1.x86_64.rpm
	ssh root@${server} "rpm -ivh netperf-2.6.0-9.1.x86_64.rpm"
	python get-pip.py
	pip --version
	pip install flent
	check_exit_status "Successfully installed packages for FLENT on client VM ${client} and server VM ${server}"
	UpdateSummary "Installed required packages for FLENT-TEST on both client VM ${client} and server VM ${server}"
	LogMsg "flushing the iptables and disabling the firewalld daemon on client VM ${client} and server VM ${server}"
	iptables -F
	ssh root@${server} "iptables -F"
	systemctl disable firewalld
	ssh root@${server} "systemctl disable firewalld"
	check_exit_status "Successfully flushed the iptables and disabled the firewalld daemon on client VM ${client} and server ${server}"
	UpdateSummary "Completed flushing iptables and disabling firewalld daemon on both client VM ${client} and server VM ${server}"
	LogMsg "Starting NETSERVER on server VM ${server}"
	ssh root@${server} "netserver -p 12865"
	check_exit_status "Successfully started NETSERVER on server VM ${server}"
	UpdateSummary "Successfully started NETSERVER on server VM ${server} & FLENT_CONFIGURED_AND_READY_FOR_TEST"
	echo "FLENT_CONFIGURED_AND_READY_FOR_TEST"
}

#######################################################################
#
# config_flent_UBUNTU()
#  
#######################################################################

function config_flent_Ubuntu
{
    local distro_version=`detect_linux_distribution_version`
    local distribution=`detect_distribution`
    
	if [ x$host_version == "x" ]; then
        host_version=`dmesg | grep "Host Build" | sed "s/.*Host Build://"|sed "s/^.*-\([0-9]*\.[0-9]*\)-.*/\1 /"`
        if [ x$host_version == "x" ]; then
            LogMsg "Unable to find Host version"
            UpdateSummary "ABORTED"
        fi
    fi
	
	LogMsg "Adding the tohojo/flent repository and downloading the python-matplotlib package on client VM ${client}"
	add-apt-repository ppa:tohojo/flent -y 
	wget http://packages.ubuntu.com/precise/python-matplotlib
	check_exit_status "Successfully added the tohojo/flent repository and downloaded the python-matplotlib package on client VM ${client}"
	UpdateSummary "Completed the download of required packages and adding repository"
	LogMsg "Updating the repos.... on client VM ${client} and server VM ${server}"
	updaterepos
	ssh root@${server} "apt-get update"
	check_exit_status "Successfully updated the repos.... on client VM ${client} and server VM ${server}"
	LogMsg "Installing packages for FLENT on client VM ${client} and server VM ${server}"
	install_package "netperf"
	ssh root@${server} "apt-get install -y netperf"
	install_package "flent"
	install_package "python-matplotlib"
	check_exit_status "Successfully installed packages for FLENT on client VM ${client} and server VM ${server}"
	UpdateSummary "Installed required packages for FLENT-TEST on both client VM ${client} and server VM ${server}"
	UpdateSummary "FLENT_CONFIGURED_AND_READY_FOR_TEST"
	echo "FLENT_CONFIGURED_AND_READY_FOR_TEST"
}

#######################################################################
#
# config_flent_SLES12SP2()
#
#######################################################################

function config_flent_SLES12SP2
{
    local distro_version=`detect_linux_distribution_version`
    local distribution=`detect_distribution`
    
	if [ x$host_version == "x" ]; then
        host_version=`dmesg | grep "Host Build" | sed "s/.*Host Build://"|sed "s/^.*-\([0-9]*\.[0-9]*\)-.*/\1 /"`
        if [ x$host_version == "x" ]; then
            LogMsg "Unable to find Host version"
            UpdateSummary "ABORTED"
        fi
    fi
	
	LogMsg "Downloading required packages for FLENT on client VM ${client} and server VM ${server}"
	wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/assmannst/RHEL_5/x86_64/netperf-2.6.0-9.1.x86_64.rpm
	ssh root@${server} "wget ftp://ftp.pbone.net/mirror/ftp5.gwdg.de/pub/opensuse/repositories/home:/assmannst/RHEL_5/x86_64/netperf-2.6.0-9.1.x86_64.rpm"
	wget https://bootstrap.pypa.io/get-pip.py
	check_exit_status "Successfully downloaded required packages for FLENT on client VM ${client} and server VM ${server}"
	UpdateSummary "Downloaded required packages for FLENT-TEST on both client VM ${client} and server VM ${server}"
	LogMsg "Installing packages for FLENT on client VM ${client} and server VM ${server}"
	rpm -ivh netperf-2.6.0-9.1.x86_64.rpm
	ssh root@${server} "rpm -ivh netperf-2.6.0-9.1.x86_64.rpm"
	python get-pip.py
	pip --version
	pip install flent
	check_exit_status "Successfully installed packages for FLENT on client VM ${client} and server VM ${server}"
	UpdateSummary "Installed required packages for FLENT-TEST on both client VM ${client} and server VM ${server}"
	LogMsg "flushing the iptables and disabling the firewalld daemon on client VM ${client} and server VM ${server}"
	iptables -F
	systemctl disable SuSEfirewall2.service
	ssh root@${server} "iptables -F"
	ssh root@${server} "systemctl disable SuSEfirewall2.service"
	check_exit_status "Successfully flushed the iptables and disabled the firewalld daemon on client VM ${client} and server VM ${server}"
	UpdateSummary "Completed flushing iptables and disabling firewalld daemon on both client VM ${client} and server VM ${server}"
	LogMsg "Starting NETSERVER on server VM ${server}"
	ssh root@${server} "netserver -p 12865"
	check_exit_status "Successfully started NETSERVER on server VM ${server}"
	UpdateSummary "Successfully started NETSERVER on server VM ${server} & FLENT_CONFIGURED_AND_READY_FOR_TEST"
	echo "FLENT_CONFIGURED_AND_READY_FOR_TEST"
}

#######################################################################
#
# config_flent_CentOS()
#
#######################################################################

config_flent_CentOS()
{
    local distro_version=`detect_linux_ditribution_version`
    LogMsg "Unsupported OS version $distro_version"
    UpdateSummary "ABORTED"
}

#######################################################################
#
# Execution starts from here
#
#######################################################################

if [ -e ${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    errMsg="Error: missing ${CONSTANTS_FILE} file"
    LogMsg "${errMsg}"
    UpdateTestState $ICA_TESTABORTED
    exit 10
fi

if [ ! ${server} ]; then
	errMsg="Please add/provide value for server in constants.sh. server=<server ip>"
	LogMsg "${errMsg}"
	echo "${errMsg}" >> ./summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi
if [ ! ${client} ]; then
	errMsg="Please add/provide value for client in constants.sh. client=<client ip>"
	LogMsg "${errMsg}"
	echo "${errMsg}" >> ./summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

if [ ! ${testDuration} ]; then
	errMsg="Please add/provide value for testDuration in constants.sh. testDuration=60"
	LogMsg "${errMsg}"
	echo "${errMsg}" >> ./summary.log
	UpdateTestState $ICA_TESTABORTED
	exit 1
fi

host_version=$1
ResetLogFiles

if [ x$host_version == "x" ]; then
    host_version=`dmesg | grep "Host Build" | sed "s/.*Host Build://"|sed "s/^.*-\([0-9]*\.[0-9]*\)-.*/\1 /"`
    if [ x$host_version == "x" ]; then
        LogMsg "Unable to find Host version"
        LogMsg "Usage: 'bash $0 <host version>
        Example:
        bash $0 6.2 #for Windows Server 2012 host
        bash $0 6.3 #for Windows Server 2012 R2 host
        bash $0 10.0 #for Windows Server 2016 host"

        echo "Usage: 'bash $0 <host version>
        Example:
        bash $0 6.2 #for Windows Server 2012 host
        bash $0 6.3 #for Windows Server 2012 R2 host
        bash $0 10.0 #for Windows Server 2016 host"
        UpdateSummary "ABORTED"
		UpdateTestState $ICA_TESTABORTED
    fi
fi

linux_distribution_type=`detect_distribution`

if [ "${linux_distribution_type}" ==  "Ubuntu" ]; then
    result=`config_flent_Ubuntu`
elif [ "${linux_distribution_type}"  == "RHEL" ]; then
    result=`config_flent_RHEL`
elif [ "${linux_distribution_type}" == "CentOS" ]; then
    result=`config_flent_CentOS`
elif [ "${linux_distribution_type}" == "SLES" ]; then
    result=`config_flent_SLES12SP2`
else
    
	echo "Error: '$linux_distribution_type' Unsupported Distribution!"

fi

if echo $result | grep "FLENT_CONFIGURED_AND_READY_FOR_TEST" ; then
    UpdateSummary "FLENT_CONFIGURED_AND_READY_FOR_TEST"
else
    UpdateSummary "FLENT_CONFIG_FAILED"
	UpdateTestState $ICA_TESTFAILED
fi

###################################################################################################
# 
# Testing the "Realtime Respond Under Load" by using FLENT
#
###################################################################################################
	
	LogMsg "Running FLENT command from client VM ${client}"
	flent rrul -l 120 -H ${server}
	check_exit_status "Successfully executed the FLENT command"
	UpdateTestState $ICA_TESTRUNNING
	flent rrul -l 300 -H ${server}
	LogMsg "Running FLENT command from client VM ${client}"
	check_exit_status "Successfully executed the FLENT command"
	UpdateSummary "Successfully executed the FLENT command"
	UpdateTestState $ICA_TESTCOMPLETED