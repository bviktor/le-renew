#!/bin/sh

### VARIABLES

# directory locations
export ROOT_DIR=$(dirname $0)
TEMP_DIR="${ROOT_DIR}/tmp"

# we can't send an email alert because SMTP settings are missing
if [ ! -f "${ROOT_DIR}/le-config.sh" ]
then
    cp "${ROOT_DIR}/le-config.sh.example" "${ROOT_DIR}/le-config.sh"
    echo 'Error: le-config.sh is missing!'
    echo 'Now I have created one, please edit it, then run le-renew.sh again.'
    exit 1
fi

# file locations
MAIL_FILE="${TEMP_DIR}/mail.txt"
LOG_FILE="${TEMP_DIR}/log.txt"

# parse config file
. "${ROOT_DIR}/le-config.sh"

# domain list
export DOM_LIST="${ROOT_DIR}/le-domains.txt"

# don't break at spaces
IFS=$'\n'

# command to request a Let's Encrypt cert
LE_CMD='letsencrypt certonly --renew-by-default'

# Let's Encrypt main config folder
LE_DIR='/etc/letsencrypt'

# cert renewal config folder
export CONF_DIR="${LE_DIR}/renewal"

# cert folder
export CERT_DIR="${LE_DIR}/live"

if [ ${DEBUG} -eq 1 ]
then
    export EXEC='echo'
    CURL_FLAGS='--verbose'
else
    export EXEC='eval'
    CURL_FLAGS='--silent'
fi

# nicely formatted date
TODAY=$(date +%Y-%m-%d)

# counters
DOM_COUNT=0
FAIL_COUNT=0
WWW=0
FAIL=0



### FUNCTIONS

dom_echo ()
{
    echo "$1" >> ${DOM_LIST}
}

renew_cert ()
{
    # FIXME make sure letsencrypt doesn't ask any questions
    #sed -i 's/renew_by_default = False/renew_by_default = True/g' "${CONF_DIR}/${1}.conf"

    # deal with unary operator expected bullshit
    WWWF=$2

    if [ -z ${WWWF} ]
    then
	WWWF=0
    fi

    if [ ${WWWF} -eq 1 ]
    then
        ${EXEC} "${LE_CMD} -d ${1} -d www.${1}" 2>${LOG_FILE}
    else
	${EXEC} "${LE_CMD} -d ${1}" 2>${LOG_FILE}
    fi

    return $?
}

mail_header ()
{
    echo "To: ${RCPT}" > ${MAIL_FILE}
    echo "Subject: Let's Encrypt Renewal Summary ${TODAY} @ ${HOSTNAME}" >> ${MAIL_FILE}
    echo "Mime-Version: 1.0;" >> ${MAIL_FILE}
    echo "Content-Type: text/html; charset=UTF-8;" >> ${MAIL_FILE}
    echo "" >> ${MAIL_FILE}
    echo "<html><head><style type=\"text/css\">" >> ${MAIL_FILE}
    echo "span.fail { color: #f00; font-weight: bold; } span.success { color: #0c0; }" >> ${MAIL_FILE}
    echo "</style></head><body><div>" >> ${MAIL_FILE}
}

mail_footer ()
{
    echo "</div></body></html>" >> ${MAIL_FILE}
}

mail_echo ()
{
    echo "$1<br />" >> ${MAIL_FILE}    
    echo "$1"
}

check_cert ()
{
    mail_echo $(openssl x509 -in $1 -noout -subject)
    mail_echo $(openssl x509 -in $1 -noout -issuer)
    mail_echo $(openssl x509 -in $1 -noout -startdate)
    mail_echo $(openssl x509 -in $1 -noout -enddate)
    mail_echo $(openssl x509 -in $1 -noout -fingerprint)
}

finish ()
{
    mail_footer
    ${EXEC} "curl ${CURL_FLAGS} --ssl-reqd --mail-from ${SMTP_SENDER} --mail-rcpt ${RCPT} --user ${SMTP_USER} --upload-file ${MAIL_FILE} --url ${SMTP_HOST}"
}



### OPERATIONS

# initial cleanup
rm -rf ${TEMP_DIR}
mkdir -p ${TEMP_DIR}

# email header
${EXEC} "mail_header"

# check domain list
if [ ! -f ${DOM_LIST} ]
then
    mail_echo 'Error: le-domains.txt is missing!'
    mail_echo 'Now I have created one, please edit it, then run le-renew.sh again.'
    dom_echo '# Please list the domains that will be served from this host.'
    dom_echo '# One entry per line.'
    dom_echo '# Entries that are not subdomains will automatically'
    dom_echo '# request the www subdomain, too.'

    finish
    exit 2
fi

# check command availability
for CMD in curl letsencrypt systemctl
do
    which ${CMD}>/dev/null 2>&1
    if [ $? -ne 0 ]
    then
	mail_echo "Error: ${CMD} is not available on your system!"
	mail_echo 'Please install it before using le-renew.'

	finish
	exit 3
    fi
done

# execute pre-renew hooks
# run them regardless of $DEBUG so that we can see the commands inside the hooks
for HOOK in $(ls -1 ${ROOT_DIR}/hook-pre/*.sh 2>/dev/null)
do
    eval ${HOOK}
done

# make sure port 80 is available
${EXEC} "systemctl stop ${WEBSRV}"

# don't parse lines starting with #
for DOM in $(grep -v ^# ${DOM_LIST})
do
    FAIL=0
    let "DOM_COUNT++"
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
	let "FAIL_COUNT++"

	# don't run till eternity
	if [ ${FAIL_COUNT} -ge 20 ]
	then
	    FAIL=1
	    break
	else
	    # don't spam too much
	    sleep 60
	    renew_cert ${DOM} ${WWW}
	fi
    done

    ${EXEC} "check_cert ${CERT_DIR}/${DOM}/cert.pem"

    if [ ${FAIL} -eq 1 ]
    then
	mail_echo ""
	mail_echo "Result: <span class=\"fail\">FAILURE</span>"

	# include the last error
	while read ERR
	do
	    mail_echo ${ERR}
	done < ${LOG_FILE}
    else
	mail_echo ""
	mail_echo "Result: <span class=\"success\">success</span>"
    fi

    mail_echo "----------"
done

${EXEC} "systemctl start ${WEBSRV}"

if [ ${DOM_COUNT} -eq 0 ]
then
    mail_echo 'Error: no domains in le-domains.txt!'
    mail_echo 'Please add at least one.'

    finish
    exit 4
fi

# execute post-renew hooks
# run them regardless of $DEBUG so that we can see the commands inside the hooks
for HOOK in $(ls -1 ${ROOT_DIR}/hook-post/*.sh 2>/dev/null)
do
    eval ${HOOK}
done

finish
exit 0
