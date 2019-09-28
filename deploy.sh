# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    deploy.sh                                          :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: taethan <marvin@42.fr>                     +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2019/09/28 12:54:04 by taethan           #+#    #+#              #
#    Updated: 2019/09/28 12:54:10 by taethan          ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

# в настройках виртуальной машины нужно обязательно заменить NAT на Bridged Adapter

# виртуалка на 8 гб, один диск 4,2 гб, второй остальное
# установил дебиан 9.11 без всего, без гуи, бут лоадер GRUB
# создан пользователь taethan

# закомментить или удалить в /etc/apt/sources.list
# deb cdrom:[Debian GNU/Linux 9.11.0 _Stretch_ - Official amd64 DVD Binary-1 20190908-18:12]/ stretch contrib main

apt-get update -y
apt-get upgrade -y

apt-get install sudo vim ufw portsentry git net-tools apache2 rsync fail2ban mailutils -y

# добавил юзера taethan в /etc/sudoers
# User privilege specification
# root    ALL=(ALL:ALL) ALL
# taethan ALL=(ALL:ALL) NOPASSWD:ALL

# проблема с locale , нужно выполнить:
# export LC_ALL="en_US.UTF-8"
# возможно потребуется sudo dpkg-reconfigure locales или что-то ещё

# нужно задать static ip
# добавить изменения в файл /etc/network/interfaces чтобы стало так:
'
#The primary network interface
auto enp0s3
'

# далее нужно настроить сеть со статическим ip, создадть файл с именем 
# enp0s3 в каталоге /etc/network/interfaces.d/
# и прописать туда
'
iface enp0s3 inet static
      address 192.168.20.217
      netmask 255.255.255.252
      gateway 192.168.254.254
'

sudo service networking restart
# проверить результат командой ip addr

# изменить стандартный порт ssh
sudo vim /etc/ssh/sshd_config
# порт 22 изменить на любой в промежутке от 49152 до 65535
# беру порт 55555

# теперь можно залогиниться через ssh
ssh taethan@192.168.20.217

# настроить доступ ssh с publickeys
# нужно сгенерировать пару публик\приват rsa ключей на хосте (macos)
ssh-keygen -t rsa
# сгенерируются id_rsa и id_rsa.pub (который нужно передать на сервер)
ssh-copy-id -i .ssh/id_rsa.pub taethan@192.168.20.217
# ключ автоматически добавляется в ~/.ssh/authorized_keys на сервер

# чтобы больше не вводить пароль нужно настроить ssh агент ssh-add
sudo vim /etc/ssh/sshd.conf
# PermitRootLogin no
# PasswordAuthentication no

# перезапустить ssh
sudo service sshd restart

# проверить UFW
sudo ufw status
# если выключен, то
sudo ufw enable

# задать правила фаерволу
sudo ufw allow 55555/tcp          # (ssh)
sudo ufw allow 80/tcp             # (http)
sudo ufw allow 443                # (https)
sudo ufw allow ssh  

# задать настройки против дудоса через fail2ban
sudo vim /etc/fail2ban/jail.conf

'
[sshd]
enabled = true
port    = 42
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
bantime = 600

# добавить после HTTP servers
[http-get-dos]
enabled = true
port = http,https
filter = http-get-dos
logpath = /var/log/apache2/access.log
maxretry = 300
findtime = 300
#ban for 5 minutes
bantime = 600
action = iptables[name=HTTP, port=http, protocol=tcp]
'

# добавить фильтр http-get-dos
sudo vim /etc/fail2ban/filter.d/http-get-dos.conf
# в него добавить:

'
[Definition]
failregex = ^<HOST> -.*"(GET|POST).*
ignoreregex =
'

# добавить разрешение для пинга
sudo vim /etc/ufw/before.rules

'
-A ufw-before-output -p icmp --icmp-type destination-unreachable -j ACCEPT
-A ufw-before-output -p icmp --icmp-type source-quench -j ACCEPT
-A ufw-before-output -p icmp --icmp-type time-exceeded -j ACCEPT
-A ufw-before-output -p icmp --icmp-type parameter-problem -j ACCEPT
-A ufw-before-output -p icmp --icmp-type echo-request -j ACCEPT
'

# теперь перезагрузить fail2ban и фаервол
sudo service fail2ban restart
sudo ufw reload

# защита от сканирования портов, настроить portsentry
sudo vim /etc/portsentry/portsentry.conf
'
BLOCK_UDP="1"
BLOCK_TCP="1"
'

# затем закомментить KILL_ROUTE который стоит и раскомментить
'
KILL_ROUTE="/sbin/iptables -I INPUT -s $TARGET$ -j DROP"
'
# закоментить ещё
'
KILL_HOSTS_DENY="ALL: $TARGET$ : DENY
'

# перезапустить portsentry
sudo service portsentry restart

# отключить ненужные сервисы
sudo systemctl disable console-setup
sudo systemctl disable keyboard-setup
sudo systemctl disable syslog

# создать update.sh
echo "sudo apt-get update -y >> /var/log/update_script.log" >> ~/update.sh
echo "sudo apt-get upgrade -y >> /var/log/update_script.log" >> ~/update.sh

# добавить задание в cron (https://crontab.guru/ в помощь)
sudo crontab -e
# добавить:
'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin

@reboot sudo ~/update.sh
0 4 * * 6 sudo ~/update.sh
'

# мониторинг изменений в cron
sudo vim ~/cronMonitor.sh
# добавить туда:

#!/bin/bash

FILE="/var/tmp/checksum"
FILE_TO_WATCH="/var/spool/cron/crontabs/taethan"
MD5VALUE=$(sudo md5sum $FILE_TO_WATCH)

if [ ! -f $FILE ]
then
	 echo "$MD5VALUE" > $FILE
	 exit 0;
fi;

if [ "$MD5VALUE" != "$(cat $FILE)" ];
	then
	echo "$MD5VALUE" > $FILE
	echo "$FILE_TO_WATCH has been modified ! '*_*" | mail -s "$FILE_TO_WATCH modified !" root
fi;

# добавить задание в крон
crontab -e

'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin

@reboot sudo ~/update.sh
0 4 * * 6 sudo ~/update.sh
0 0 * * * sudo ~/cronMonitor.sh
'

# задать нужные права 
sudo chmod 755 cronMonitor.sh
sudo chmod 755 update.sh
sudo chown taethan /var/mail/taethan

# включить крон, если он не алё
sudo systemctl enable cron

# задеплоить веб страницу в 
cd /var/www/html/
# проще всего задеплоить с гитхаба из командной строки сервера
'
Что значит развернуть приложение?
Веб-приложение разделено на две части.

Код на стороне клиента: это код вашего интерфейса пользователя. 
Это статические файлы, которые не меняются на протяжении всей жизни вашего приложения. 
Статические файлы должны где-то существовать, чтобы пользователи могли загружать и 
запускать их в своем браузере на стороне клиента. 
Код на стороне сервера: это касается всей логики вашего приложения. 
Он должен быть запущен на сервере, обычно виртуальном, 
так же, как вы запускаете его при локальной разработке.
'

# ещё необходимо сгенерировать ssl сертификат
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt
sudo vim /etc/apache2/conf-available/ssl-params.conf
# добавить туда:
'
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLHonorCipherOrder On

Header always set X-Frame-Options DENY
Header always set X-Content-Type-Options nosniff

SSLCompression off
SSLUseStapling on
SSLStaplingCache "shmcb:logs/stapling-cache(150000)"

SSLSessionTickets Off
'

# изменить файл
sudo vim /etc/apache2/sites-available/default-ssl.conf
'
<IfModule mod_ssl.c>
	<VirtualHost _default_:443>
		ServerAdmin taethan@student.21-school.ru
		ServerName	192.168.20.217

		DocumentRoot /var/www/html

		ErrorLog ${APACHE_LOG_DIR}/error.log
		CustomLog ${APACHE_LOG_DIR}/access.log combined

		SSLEngine on

		SSLCertificateFile	    /etc/ssl/certs/apache-selfsigned.crt
		SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key

		<FilesMatch "\.(cgi|shtml|phtml|php)$">
				SSLOptions +StdEnvVars
		</FilesMatch>
		<Directory /usr/lib/cgi-bin>
				SSLOptions +StdEnvVars
		</Directory>

	</VirtualHost>
</IfModule>
'

# отредактировать файл
sudo vim /etc/apache2/sites-available/000-default.conf
'
<VirtualHost *:80>

	ServerAdmin webmaster@localhost
	DocumentRoot /var/www/html

	Redirect "/" "https://192.168.20.217/"

	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
'
# для запуска конфига ввести команды
sudo a2enmod ssl
sudo a2enmod headers
sudo a2ensite default-ssl
sudo a2enconf ssl-params
sudo systemctl reload apache2

# shasum < "/goinfre/VirtualBox/debian9/debian9.vdi"
# shasum -a 256 debian9.vdi

https://github.com/AntipovDS/site.git
https://192.168.20.217/#




# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    deploy.sh                                          :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: taethan <marvin@42.fr>                     +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2019/09/28 12:54:04 by taethan           #+#    #+#              #
#    Updated: 2019/09/28 12:54:10 by taethan          ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

# в настройках виртуальной машины нужно обязательно заменить NAT на Bridged Adapter

# виртуалка на 8 гб, один диск 4,2 гб, второй остальное
# установил дебиан 9.11 без всего, без гуи, бут лоадер GRUB
# создан пользователь taethan

# закомментить или удалить в /etc/apt/sources.list
# deb cdrom:[Debian GNU/Linux 9.11.0 _Stretch_ - Official amd64 DVD Binary-1 20190908-18:12]/ stretch contrib main

apt-get update -y
apt-get upgrade -y

apt-get install sudo vim ufw portsentry net-tools apache2 rsync fail2ban mailutils -y

# добавил юзера taethan в /etc/sudoers
# User privilege specification
# root    ALL=(ALL:ALL) ALL
# taethan ALL=(ALL:ALL) NOPASSWD:ALL

# проблема с locale , нужно выполнить:
# export LC_ALL="en_US.UTF-8"
# возможно потребуется sudo dpkg-reconfigure locales или что-то ещё

# нужно задать static ip
# добавить изменения в файл /etc/network/interfaces чтобы стало так:
'
#The primary network interface
auto enp0s3
'

# далее нужно настроить сеть со статическим ip, создадть файл с именем 
# enp0s3 в каталоге /etc/network/interfaces.d/
# и прописать туда
'
iface enp0s3 inet static
      address 192.168.20.217
      netmask 255.255.255.252
      gateway 192.168.254.254
'

sudo service networking restart
# проверить результат командой ip addr

# изменить стандартный порт ssh
sudo vim /etc/ssh/sshd_config
# порт 22 изменить на любой в промежутке от 49152 до 65535
# беру порт 55555

# теперь можно залогиниться через ssh
ssh taethan@192.168.20.217

# настроить доступ ssh с publickeys
# нужно сгенерировать пару публик\приват rsa ключей на хосте (macos)
ssh-keygen -t rsa
# сгенерируются id_rsa и id_rsa.pub (который нужно передать на сервер)
ssh-copy-id -i .ssh/id_rsa.pub taethan@192.168.20.217
# ключ автоматически добавляется в ~/.ssh/authorized_keys на сервер

# чтобы больше не вводить пароль нужно настроить ssh агент ssh-add
sudo vim /etc/ssh/sshd.conf
# PermitRootLogin no
# PasswordAuthentication no

# перезапустить ssh
sudo service sshd restart

# проверить UFW
sudo ufw status
# если выключен, то
sudo ufw enable

# задать правила фаерволу
sudo ufw allow 55555/tcp          # (ssh)
sudo ufw allow 80/tcp             # (http)
sudo ufw allow 443                # (https)
sudo ufw allow ssh  

# задать настройки против дудоса через fail2ban
sudo vim /etc/fail2ban/jail.conf

'
[sshd]
enabled = true
port    = 42
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
bantime = 600

# добавить после HTTP servers
[http-get-dos]
enabled = true
port = http,https
filter = http-get-dos
logpath = /var/log/apache2/access.log
maxretry = 300
findtime = 300
#ban for 5 minutes
bantime = 600
action = iptables[name=HTTP, port=http, protocol=tcp]
'

# добавить фильтр http-get-dos
sudo vim /etc/fail2ban/filter.d/http-get-dos.conf
# в него добавить:

'
[Definition]
failregex = ^<HOST> -.*"(GET|POST).*
ignoreregex =
'

# добавить разрешение для пинга
sudo vim /etc/ufw/before.rules

'
-A ufw-before-output -p icmp --icmp-type destination-unreachable -j ACCEPT
-A ufw-before-output -p icmp --icmp-type source-quench -j ACCEPT
-A ufw-before-output -p icmp --icmp-type time-exceeded -j ACCEPT
-A ufw-before-output -p icmp --icmp-type parameter-problem -j ACCEPT
-A ufw-before-output -p icmp --icmp-type echo-request -j ACCEPT
'

# теперь перезагрузить fail2ban и фаервол
sudo service fail2ban restart
sudo ufw reload

# защита от сканирования портов, настроить portsentry
sudo vim /etc/portsentry/portsentry.conf
'
BLOCK_UDP="1"
BLOCK_TCP="1"
'

# затем закомментить KILL_ROUTE который стоит и раскомментить
'
KILL_ROUTE="/sbin/iptables -I INPUT -s $TARGET$ -j DROP"
'
# закоментить ещё
'
KILL_HOSTS_DENY="ALL: $TARGET$ : DENY
'

# перезапустить portsentry
sudo service portsentry restart

# отключить ненужные сервисы
sudo systemctl disable console-setup
sudo systemctl disable keyboard-setup
sudo systemctl disable syslog

# создать update.sh
echo "sudo apt-get update -y >> /var/log/update_script.log" >> ~/update.sh
echo "sudo apt-get upgrade -y >> /var/log/update_script.log" >> ~/update.sh

# добавить задание в cron (https://crontab.guru/ в помощь)
sudo crontab -e
# добавить:
'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin

@reboot sudo ~/update.sh
0 4 * * 6 sudo ~/update.sh
'

# мониторинг изменений в cron
sudo vim ~/cronMonitor.sh
# добавить туда:

#!/bin/bash

FILE="/var/tmp/checksum"
FILE_TO_WATCH="/var/spool/cron/crontabs/taethan"
MD5VALUE=$(sudo md5sum $FILE_TO_WATCH)

if [ ! -f $FILE ]
then
	 echo "$MD5VALUE" > $FILE
	 exit 0;
fi;

if [ "$MD5VALUE" != "$(cat $FILE)" ];
	then
	echo "$MD5VALUE" > $FILE
	echo "$FILE_TO_WATCH has been modified ! '*_*" | mail -s "$FILE_TO_WATCH modified !" root
fi;

# добавить задание в крон
crontab -e

'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin

@reboot sudo ~/update.sh
0 4 * * 6 sudo ~/update.sh
0 0 * * * sudo ~/cronMonitor.sh
'

# задать нужные права 
sudo chmod 755 cronMonitor.sh
sudo chmod 755 update.sh
sudo chown taethan /var/mail/taethan

# включить крон, если он не алё
sudo systemctl enable cron

# задеплоить веб страницу в 
cd /var/www/html/
# проще всего задеплоить с гитхаба из командной строки сервера
'
Что значит развернуть приложение?
Веб-приложение разделено на две части.

Код на стороне клиента: это код вашего интерфейса пользователя. 
Это статические файлы, которые не меняются на протяжении всей жизни вашего приложения. 
Статические файлы должны где-то существовать, чтобы пользователи могли загружать и 
запускать их в своем браузере на стороне клиента. 
Код на стороне сервера: это касается всей логики вашего приложения. 
Он должен быть запущен на сервере, обычно виртуальном, 
так же, как вы запускаете его при локальной разработке.
'

# ещё необходимо сгенерировать ssl сертификат
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt
sudo vim /etc/apache2/conf-available/ssl-params.conf
# добавить туда:
'
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH
SSLProtocol All -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
SSLHonorCipherOrder On

Header always set X-Frame-Options DENY
Header always set X-Content-Type-Options nosniff

SSLCompression off
SSLUseStapling on
SSLStaplingCache "shmcb:logs/stapling-cache(150000)"

SSLSessionTickets Off
'

# изменить файл
sudo vim /etc/apache2/sites-available/default-ssl.conf
'
<IfModule mod_ssl.c>
	<VirtualHost _default_:443>
		ServerAdmin taethan@student.21-school.ru
		ServerName	192.168.20.217

		DocumentRoot /var/www/html

		ErrorLog ${APACHE_LOG_DIR}/error.log
		CustomLog ${APACHE_LOG_DIR}/access.log combined

		SSLEngine on

		SSLCertificateFile	    /etc/ssl/certs/apache-selfsigned.crt
		SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key

		<FilesMatch "\.(cgi|shtml|phtml|php)$">
				SSLOptions +StdEnvVars
		</FilesMatch>
		<Directory /usr/lib/cgi-bin>
				SSLOptions +StdEnvVars
		</Directory>

	</VirtualHost>
</IfModule>
'

# отредактировать файл
sudo vim /etc/apache2/sites-available/000-default.conf
'
<VirtualHost *:80>

	ServerAdmin webmaster@localhost
	DocumentRoot /var/www/html

	Redirect "/" "https://192.168.20.217/"

	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined

</VirtualHost>
'
# для запуска конфига ввести команды
sudo a2enmod ssl
sudo a2enmod headers
sudo a2ensite default-ssl
sudo a2enconf ssl-params
sudo systemctl reload apache2

# как вариант можно еще деплоить
rsync -avh -e ssh /users/taethan/42/site taethan@192.168.20.217:/var/www/html/
rsync -avz /users/taethan/42/site taethan@192.168.20.217:/var/www/html/

# создать файл: "/etc/rsyncd.conf" и вписать:
'
  max connections = 2
  log file = /var/log/rsync.log
  timeout = 300
  
  [pub]
  	comment = Random things available for download
  	path = /var/www/html/
  	read only = yes
  	list = yes 
  	uid = nogroup
  	gid = nogroup
  	auth users = pub
  	secrets file = /etc/rsyncd.secrets
'
# создать файл "/etc/rsyncd.secrets", добавить туда:
'pub:pub'
# потом сделать 
chmod 600 /etc/rsyncd.secrets

# shasum < "/goinfre/VirtualBox/debian9/debian9.vdi"
# shasum -a 256 debian9.vdi
