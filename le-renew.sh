#!/bin/sh

# make sure the script can find the domain list even when invoked from a different dir
DIR=$(dirname $0)

# parse config file
. "${DIR}/le-config.sh"

# parse domain list
DOMLIST="${DIR}/le-domains.txt"

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
    EXEC='echo'
else
    EXEC='eval'
fi

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

# don't parse lines starting with #
for DOM in $(grep -v ^# ${DOMLIST})
do
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
