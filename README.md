# le-renew

Quick-n-dirty script for automatically renewing Let's Encrypt certificates.

* Request an initial certificate with `letsencrypt certonly -d foobar.com -d www.foobar.com`.
* List your domains in `le-domains.txt`. Lines starting with `#` will be ignored.
For domains that are not subdomains, the `www` subdomain will be requested automatically, too.
E.g.: if you add `foobar.com`, the cert will contain `foobar.com` and `www.foobar.com`.
* Adjust `le-config.sh` as per your environment.
* Set up hooks if needed.
* Install the cronjob under `/etc/cron.d`, then restart the cron daemon.

## Hooks

You can add pre-renew hooks under the `hook-pre` folder and post-renew hooks under the `hook-post` folder.
It is recommended to use `${EXEC}` for evey command - this way the hook will respect the `DEBUG` variable,
as set in `le-config.sh`.

An example `hook-post/znc.sh` hook:

~~~
#!/bin/sh

# example post-renew hook to regenerate the ZNC cert file after each renew

# CAUTION: here we assume there's only one domain
DOM=$(grep -v "^#" ${DOMLIST})

ZNC_DIR='/var/lib/znc/.znc'

${EXEC} "mv --force ${ZNC_DIR}/znc.pem ${ZNC_DIR}/znc.pem.orig"

if [ ! -f "${ZNC_DIR}/dhparam.pem" ]
then
    ${EXEC} "openssl dhparam -out ${ZNC_DIR}/dhparam.pem 4096"
fi

${EXEC} "cat ${CERT_DIR}/${DOM}/privkey.pem > ${ZNC_DIR}/znc.pem"
${EXEC} "cat ${CERT_DIR}/${DOM}/cert.pem >> ${ZNC_DIR}/znc.pem"
${EXEC} "cat ${ZNC_DIR}/dhparam.pem >> ${ZNC_DIR}/znc.pem"

${EXEC} "/bin/systemctl restart znc.service"
~~~
