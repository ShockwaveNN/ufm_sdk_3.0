#!/bin/bash
#
# Copyright © 2019-2021 NVIDIA CORPORATION & AFFILIATES. ALL RIGHTS RESERVED.
#
# This software product is a proprietary product of Nvidia Corporation and its affiliates
# (the "Company") and all right, title, and interest in and to the software
# product, including all associated intellectual property rights, are and
# shall remain exclusively with the Company.
#
# This software product is governed by the End User License Agreement
# provided with the software product.
#

SLURM_SERVICE_PATH='/lib/systemd/system/slurmctld.service'
UFM_PROLOG_FILE='ufm-prolog.sh'
UFM_EPILOG_FILE='ufm-epilog.sh'
PROLOG_SLURMCTLD='PrologSlurmctld'
EPILOG_SLURMCTLD='EpilogSlurmctld'
UFM_SLURM_CONF='ufm_slurm.conf'
INSTALLING_PLUGIN='Installing UFM-SLURM integration plugin. Please wait...'
INSTALLATION_COMPLETED_SUCCESSFULLY='Installation completed successfully'
CP_FILES='Copying integration files...'
CONF_SETTINGS='Setting configurations...'
SET_UFM_SLURM_CONF="Please configure the settings of integration using the configuration file:$UFM_SLURM_CONF"
INSTALLATION_FAILED='Installation failed'
install_status=0
WORK_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

errorlog() {
    echo "ERROR: $1"
}

function copy_integration_files()
{
    declare -a intg_files=("ufm_slurm_epilog.py" "ufm_slurm_prolog.py" "ufm_slurm_utils.py" "ufm_slurm.conf" "ufm-epilog.sh" "ufm-prolog.sh" "ufm_slurm_base.py")
    for file in "${intg_files[@]}"
    do
    sudo cp -f "$file" $SLURM_DIR
    check_failure $? "Error while copying integration file: $file"
    sudo chmod 755 "$SLURM_DIR/$file"
    check_failure $? "Error while changing permissions for file: $file"
    done

}

function update_slurm_conf()
{
    # Arg #1 is the target key, Arg #2 is the new value
    CONFIG_FILE="$SLURM_DIR/slurm.conf"
    # Check if slurm.conf is exist or not
    if [ ! -f "$CONFIG_FILE" ]; then
        failure "$CONFIG_FILE does not exist! Please run this script on Slurm server."
    fi
    # Backup the original slurm conf file before update.
    sudo cp -p "$CONFIG_FILE" "$CONFIG_FILE.orig.`date \"+%Y%m%d_%H%M%S\"`"
    # Update the conf file
    if grep -q "^[ ^I]*$1[ ^I]*=" "$CONFIG_FILE"; then
        sudo sed -i -e "s@^\([ ^I]*"$1"[ ^I]*=[ ^I]*\).*\$@\1"$2"@" $CONFIG_FILE
    else
        sudo sed -i -e "\$a $1=$2" $CONFIG_FILE
    fi
}

function validate_requirements()
{
    # Check if script is running on SLURM controller
    if [ ! -f "$SLURM_SERVICE_PATH" ]; then
        failure "Slurm is not installed! Please run this script on Slurm server."
    fi
}

function failure()
{
    echo "$1"
    echo $INSTALLATION_FAILED
    exit 2
}

function check_failure()
{
    local sts=$1
    install_status=$((install_status + sts))
    if [ ! $install_status -eq 0 ]; then
    failure "$2"
fi
}

get_redhat_version() {
    local ver
    ver=`rpm -q --qf '%{VERSION}' $(rpm -qf /etc/redhat-release)`
    case ${ver} in
        7*) echo rhel7; return 0;;
        8*) echo rhel8; return 0;;
    esac
    # check may be it is euleros
    is_euleros=`rpm -qf /etc/redhat-release| grep euleros | wc -l`
    if [ $is_euleros -eq 1 ]; then
        if [[ ${ver} == 2* ]]
        then
            echo rhel7
            return 0
        fi
    fi

    echo "unknown redhat"
    return 1
}

get_os(){
    os=`rpm --eval %{_vendor}`
    echo ${os}
    if [[ ${#os} -eq 0 ]];then
        return 1
    fi
    return 0
}

get_distro(){
    local distro vendor="unknown" RPM ret

    RPM=`which rpm 2>/dev/null`
    if [[ $? -ne 0 ]];then
        echo ${vendor}
        return 1
    fi

    vendor=`get_os`
    if [ $? -eq 1 ];then
        echo ${vendor}
        return 1
    fi

    case ${vendor} in
        redhat) vendor=`get_redhat_version`;ret=$?;;
        *)     echo ${vendor}; return 1;;
    esac

    if [[ ${ret} -ne 0 ]];then
        echo "${vendor}"
        return ${ret}
    fi

    echo ${vendor}
    return 0
}

PreparePrereqRpms()  # RPMS that user is requested to install (using yum) prior to UFM Slurm Integration installation
{
    case "${distro}" in
        rhel7)
            ib_depended_rpms=( )
            ;;
        rhel8)
            ib_depended_rpms=( )
            ;;
    esac
}

CheckRPMS() {
    declare -a rpms_to_be_installed
    errmsg="The following RPM(s) are missing and required for UFM Slurm Integration installation:\n"
    export sr=0
    depended_rpms=(${ib_depended_rpms[@]})

    for rpm_name in ${depended_rpms[@]}; do
        sudo rpm -qa | grep ${rpm_name} &> /dev/null
        if [ $? -ne 0 ]; then
            errorlog "required ${rpm_name} is not installed"
            errmsg="${errmsg}  ${rpm_name}\n"
            rpms_to_be_installed=("${rpms_to_be_installed[@]}" ${rpm_name})
            sr=1
        fi
    done
    if [ ${#rpms_to_be_installed[@]} -ne 0 ]; then
       command_msg=" Please install missing RPM(s) using \"$yum install ${rpms_to_be_installed[*]}\""
       errmsg="${errmsg} ${command_msg}\n"
       errorlog errmsg
       exit 2
    fi
    return ${sr}
}

# prepare list of packages to be installed using pip
PreparePrereqPackages()
{
    python_packages_for_pip=( requests ipaddress)
    case "${distro}" in
	rhel7)
	    python_packages_for_pip=(${python_packages_for_pip[@]})
	    ;;
	rhel8)
	    python_packages_for_pip=(${python_packages_for_pip[@]})
	    ;;
    esac
}

#========================================================================================================================
# Test for (prereq) python packages that are required to install by the User, prior to UFM Slurm Integration installation
#========================================================================================================================
CheckPythonPackages() {
    sudo pip3 --version >> /dev/null
    if [ $? -eq 0 ]; then
        declare -a python_pkgs_to_be_installed
        errmsg="The following python packages are missing and required for UFM Slurm Integration installation:\n"
        export pr=0
        depended_packages=(${python_packages_for_pip[@]})
        for pkg_name in ${depended_packages[@]}; do
            sudo pip3 list | grep ${pkg_name} &> /dev/null
            if [ $? -ne 0 ]; then
                errorlog "required ${pkg_name} is not installed"
                errmsg="${errmsg}  '${pkg_name}' \n"
                python_pkgs_to_be_installed=("${python_pkgs_to_be_installed[@]}" ${pkg_name} )
                pr=1
            fi
        done
        if [ ${#python_pkgs_to_be_installed[@]} -ne 0 ]; then
            command_msg=" Please install missing python packages using \"pip3 install ${python_pkgs_to_be_installed[*]}\""
            errmsg="${errmsg} ${command_msg}"
            errorlog "${errmsg}"
            exit 2
        fi
        return ${pr}
    else
        echo "ERROR: 'pip3' is not installed. Please install 'pip3' (using 'easy_install' or any other package manager) and restart UFM Slurm Integration installation."
        exit 2
    fi
}

#============================================
# Start of UFM Slurm Integration Installation
#============================================
echo $INSTALLING_PLUGIN
distro=`get_distro`
validate_requirements
SLURM_DIR=$(dirname "$(cat $SLURM_SERVICE_PATH | grep ConditionPathExists | cut -d '=' -f2)")
PreparePrereqRpms
CheckRPMS
PreparePrereqPackages
CheckPythonPackages
echo $CP_FILES
cd $WORK_DIR; pwd
copy_integration_files
echo $CONF_SETTINGS
update_slurm_conf $PROLOG_SLURMCTLD "$SLURM_DIR/$UFM_PROLOG_FILE"
update_slurm_conf $EPILOG_SLURMCTLD "$SLURM_DIR/$UFM_EPILOG_FILE"
echo $INSTALLATION_COMPLETED_SUCCESSFULLY
echo $SET_UFM_SLURM_CONF
exit 0
