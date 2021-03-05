FROM phusion/baseimage:master-amd64
MAINTAINER Ahumaro Mendoza <ahumaro@ahumaro.com>, Dmitrii Zolotov <dzolotov@herzen.spb.ru>

CMD ["/sbin/my_init"]

ENV HOME /root
ENV DEBIAN_FRONTEND noninteractive

ADD run /etc/service/mrun/run

#Install core packages
RUN apt-get update -q -y && apt install -y logrotate && apt-get upgrade -y -q && apt-get install -y -q php php-mbstring php-zip \
    php-dom php-cli php-fpm php-gd php-curl php-apcu ca-certificates nginx git-core php-ctype php-json php-imagick openssh-server \
    php-fdomdocument php-fxsl php-simplexml php-xml php-opcache php-yaml php-xdebug && \
    apt-get clean -q && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#Get Grav
RUN rm -fR /usr/share/nginx/html/ && git clone https://github.com/getgrav/grav.git /usr/share/nginx/html/

#Install Grav
WORKDIR /usr/share/nginx/html/

RUN bin/composer.phar self-update
RUN bin/composer.phar config -g github-oauth.github.com bcd67ae676c681a2f396904be84695e173241779
RUN bin/composer.phar update
RUN bin/grav install
RUN chown www-data:www-data . && chown -R www-data:www-data *

RUN find . -type f | xargs -d '\n' chmod 664
RUN find . -type d | xargs -d '\n' chmod 775
RUN find . -type d | xargs -d '\n' chmod +s

RUN umask 0002 && chmod 777 -R assets && \
    chmod +x bin/gpm && sed -i 's/allow_url_fopen.*/allow_url_fopen = Off/ig' /etc/php/7.4/cli/php.ini && \
    sed -i 's/allow_url_fopen.*/allow_url_fopen = Off/ig' /etc/php/7.4/fpm/php.ini && \
    sed -i 's/session.gc_maxlifetime.*/session.gc_maxlifetime = 6048000/ig' /etc/php/7.4/cli/php.ini && \
    sed -i 's/session.gc_maxlifetime.*/session.gc_maxlifetime = 6048000/ig' /etc/php/7.4/fpm/php.ini && \
    sed -i 's/upload_max_filesize.*/upload_max_filesize = 256M/ig' /etc/php/7.4/fpm/php.ini && \
    sed -i 's/post_max_size.*/post_max_size = 256M/ig' /etc/php/7.4/fpm/php.ini && \
    echo "client_max_body_size 256M;" >/etc/nginx/conf.d/maxsize.conf

RUN bin/gpm install -y admin admin-addon-user-manager core-service-manager markdown-color markdown-typography  markdown-notices markdown-details markdown-collapsible markdown-fontawesome \
&& echo "Europe/Moscow" > /etc/timezone && dpkg-reconfigure tzdata && chown www-data -R /usr/share/nginx/html/cache && \
    chmod 777 -R /usr/share/nginx/html/cache 
    
# sed -i "s~\$Element\['attributes'\]\['href'\] = \$matches\[1\]~if (substr(trim(\$matches[1]),0,4)!='http') \$Element['attributes']['href'] = './'.\$matches[1]; else \$Element['attributes']['href'] = \$matches[1]~ig" /usr/share/nginx/html/system/src/Grav/Common/Markdown/ParsedownGravTrait.php

#Configure Nginx - enable gzip
RUN sed -i 's|# gzip_types|  gzip_types|' /etc/nginx/nginx.conf

RUN sed -i 's/7.2/7.4/ig' /usr/share/nginx/html/webserver-configs/nginx.conf

#Setup Grav configuration for Nginx
RUN touch /etc/nginx/grav_conf.sh && chmod +x /etc/nginx/grav_conf.sh && echo '#!/bin/bash \n\
    echo "" > /etc/nginx/sites-available/default \n\
    ok="0" \n\
    while IFS="" read line \n\
    do \n\
        if [ "$line" = "server {" ]; then \n\
            ok="1" \n\
        fi \n\
        if [ "$ok" = "1" ]; then \n\
            echo "$line" >> /etc/nginx/sites-available/default \n\
        fi \n\
        if [ "$line" = "}" ]; then \n\
            ok="0" \n\
        fi \n\
    done < /usr/share/nginx/html/webserver-configs/nginx.conf' >> /etc/nginx/grav_conf.sh

RUN /etc/nginx/grav_conf.sh && sed -i \
        -e 's|root   html|root   /usr/share/nginx/html|' \
        -e 's|127.0.0.1:9000;|unix:/var/run/php7.4-fpm.sock;|' \
        -e 's|/home/USER/www/html|/usr/share/nginx/html|ig' \
    /etc/nginx/sites-available/default

#Setup Php service
RUN mkdir -p /etc/service/php-fpm && touch /etc/service/php-fpm/run && chmod +x /etc/service/php-fpm/run && echo '#!/bin/bash \n\
exec /usr/sbin/php-fpm7.4 -F' >> /etc/service/php-fpm/run

#Setup Nginx service
RUN mkdir -p /etc/service/nginx && touch /etc/service/nginx/run && chmod +x /etc/service/nginx/run && echo '#!/bin/bash \n\
exec /usr/sbin/nginx -g "daemon off;"' >>  /etc/service/nginx/run

RUN mkdir /init && cd /usr/share/nginx/html/user/ && cp -R . /init/

RUN mkdir -p /etc/service/mrun
ADD run /etc/service/mrun/run

#Expose configuration and content volumes
VOLUME /usr/share/nginx/html/user

#Public ports
EXPOSE 22 80
