#!/bin/sh

# make sure the script can find the domain list even when invoked from a different dir
export DIR=$(dirname $0)

# parse config file
. "${DIR}/le-config.sh"

# check domain list
export DOMLIST="${DIR}/le-domains.txt"

dom_echo ()
{
    echo "$1" >> ${DOMLIST}
}

if [ ! -f ${DOMLIST} ]
then
    echo 'Error: le-domains.txt is missing!'
    echo 'Now I have created one, please edit it, then run le-renew.sh again.'
    dom_echo '# Please list the domains that will be served from this host.'
    dom_echo '# One entry per line.'
    dom_echo '# Entries that are not subdomains will automatically'
    dom_echo '# request the www subdomain, too.'
    exit 1
fi

# don't break at spaces
IFS=$'\n'

# make sure it works even in cron with different $PATH
LECMD='/bin/letsencrypt certonly --renew-by-default'

# cert renewal config folder
CONF='/etc/letsencrypt/renewal/'

# initialize the WWW param
WWW=0

if [ ${DEBUG} -eq 1 ]
then
    export EXEC='echo'
else
    export EXEC='eval'
fi

# execute pre-renew hook
# run it regardless of $DEBUG so that we can see the commands inside the hooks
eval ${DIR}/le-hook-pre.sh

# make sure port 80 is available
${EXEC} "/bin/systemctl stop ${WEBSRV}"

renew_cert ()
{
    # FIXME make sure letsencrypt doesn't ask any questions
    #sed -i 's/renew_by_default = False/renew_by_default = True/g' "${CONF}/${1}.conf"

    # deal with unary operator expected bullshit
    WWWF=$2

    if [ -z ${WWWF} ]
    then
	WWWF=0
    fi

    if [ ${WWWF} -eq 1 ]
    then
        ${EXEC} "${LECMD} -d ${1} -d www.${1}"
    else
	${EXEC} "${LECMD} -d ${1}"
    fi

    return $?
}

COUNT=0
# don't parse lines starting with #
for DOM in $(grep -v ^# ${DOMLIST})
do
    let "COUNT++"
    # if it's not a subdomain, request cert for www too
    DOTS=$(echo ${DOM} | grep -o '\.' | wc -l)
    if [ ${DOTS} -eq 1 ]
    then
	WWW=1
    else
	WWW=0
    fi

    renew_cert ${DOM} ${WWW}
    # if failed, try until succeeds
    while [ $? -ne 0 ]
    do
	# don't spam too much
	sleep 10
	renew_cert ${DOM} ${WWW}
    done
done

${EXEC} "/bin/systemctl start ${WEBSRV}"

if [ ${COUNT} -eq 0 ]
then
    echo 'Error: no domains in le-domains.txt!'
    echo 'Please add at least one.'
    exit 2
fi

# execute post-renew hook
# run it regardless of $DEBUG so that we can see the commands inside the hooks
eval ${DIR}/le-hook-post.sh

exit 0
