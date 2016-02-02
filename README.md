# le-renew
Quick-n-dirty script for automatically renewing Let's Encrypt certificates.

* List your domains in `le-domains.txt`. Lines starting with `#` will be ignored.
For domains that are not subdomains, the `www` subdomain will be requested automatically, too.
E.g.: if you add `foobar.com`, the cert will contain `foobar.com` and `www.foobar.com`.
* Adjust `le-config.sh` as per your environment.
* Request an initial certificate with `letsencrypt certonly -d foobar.com -d www.foobar.com`.
* Install the cronjob under `/etc/cron.d`, then restart the cron daemon.
