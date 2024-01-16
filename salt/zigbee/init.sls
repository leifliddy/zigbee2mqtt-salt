{% set firewall_external_access = salt['pillar.get']('firewall_external_access_zigbee') %}
{% set firewall_zone = salt['pillar.get']('firewall_zone_zigbee') %}

install_mosquitto_rpm:
  pkg.installed:
    - pkgs:
      - mosquitto
      - nodejs

create_zigbee_user:
  user.present:
    - usergroup: True
    - name:      zigbee
    - home:      /opt/zigbee2mqtt
    - shell:     /sbin/nologin
    - system:    True
    - groups: 
      - dialout

change_selinux_permissive:
  cmd.run:
    - name: setenforce 0

clone_zigbee_repo:
  git.latest:
    - name:   https://github.com/Koenkk/zigbee2mqtt.git
    - target: /opt/zigbee2mqtt
    - rev:    master
    - depth:  1
    - unless: test -d /opt/zigbee2mqtt

change_ownership_zigbee_repo:
  file.directory:
    - name:      /opt/zigbee2mqtt
    - user:      zigbee
    - group:     zigbee
    - dir_mode:  755
    - file_mode: 644
    - recurse:
      - user
      - group
      - mode

run_npm_ci:
  cmd.run:
    - name:  npm ci
    - cwd:   /opt/zigbee2mqtt
    - runas: zigbee
    
run_npm_build:
  cmd.run:
    - name:  npm run build
    - cwd:   /opt/zigbee2mqtt
    - runas: zigbee

deploy_npmrc:
  file.managed: 
    - name:   /opt/zigbee2mqtt/.npmrc
    - source: salt://zigbee/files/npmrc
    - user:   zigbee
    - group:  zigbee
    - mode:   644
    
deploy_configuration_yaml:
  file.managed: 
    - name:   /opt/zigbee2mqtt/data/configuration.yaml
    - source: salt://zigbee/files/configuration.yaml
    - user:   zigbee
    - group:  zigbee
    - mode:   644
    
deploy_secret_yaml:
  file.managed: 
    - name:   /opt/zigbee2mqtt/data/secret.yaml
    - source: salt://zigbee/files/secret.yaml
    - user:   zigbee
    - group:  zigbee
    - mode:   644    
    
deploy_zigbee2mqtt_service:
  file.managed: 
    - name:   /etc/systemd/system/zigbee2mqtt.service
    - source: salt://zigbee/files/zigbee2mqtt.service
    - user:   zigbee
    - group:  zigbee
    - mode:   644

start_enable_mosquitto:
  service.running:
    - name:   mosquitto
    - enable: True
    - reload: True
 
start_enable_zigbee2mqtt:
  service.running:
    - name:   zigbee2mqtt
    - enable: True

apply_selinux_npm_modules:
  cmd.run:
    - cwd: /tmp
    - name: |
        ausearch -c 'npm' --raw | audit2allow -M my-npm
        semodule -X 300 -i my-npm.pp
    - onlyif: systemctl is-active zigbeee2mqtt.service | grep inactive
    
start_zigbee2mqtt:
  service.running:
    - name:     zigbee2mqtt
    - requires: apply selinux_policy
    - watch: 
      - apply_selinux_npm_modules  

{% if firewall_external_access %}
firewalld_enable_start_service:
  service.running:
    - name: firewalld
    - enable: True

create_zigbee_xml:
    file.managed:
      - name: /etc/firewalld/services/zigbee.xml
      - contents: |
          <?xml version="1.0" encoding="utf-8"?>
          <service>
            <short>zigbee</short>
            <port protocol="tcp" port="8080"/>
          </service>

firewalld_reload_service:
  service.running:
    - name: firewalld
    - watch:
      - create_zigbee_xml
    
enable_firewalld_zigbee_service:
  firewalld.present:
    - name: {{ firewall_zone }}
    - services:
      - zigbee
    - require:
      - create_zigbee_xml
{% endif %}
