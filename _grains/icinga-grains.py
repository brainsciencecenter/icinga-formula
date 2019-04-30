#!/usr/bin/env python

import os
import sys
import yaml
import json
import re

g = """
default:
  command_path: /usr/lib/nagios/plugins
  check_type: passive
  warning:
  critical:
  options: 
  cmd: "{command_path}/{check_name} -w {warning} -c {critical}"

passive_check:
  user: root
  minute: 1
  hour: '*'
  days: '*'
  dom: '*'
  month: '*'
  dow: '*'

check_apt:
  cmd: "{command_path}/{check_name}"

#
# Cron thinks '%' means End of Line unless it is escaped
#
check_disk:
  critical: 5\%
  warning: 10\%
  cmd: "{command_path}/{check_name} -w {warning} -c {critical} {name}"

check_host:
  critical: 2
  warning: 1
  options: " {name}"

check_http:
  critical: 2
  warning: 1
  options: " -H {name}"

check_load:
  minute: '*/5'
  warning: 100,50,5
  critical: 200,100,10

check_procs:
  cmd: "{command_path}/{check_name} -w {warning} -c {critical} -C {name}"
  warning: 0
  critical: 0

check_sensors:
  cmd: "{command_path}/{check_name}"

check_ntp:
  critical: 2
  warning: 1
  timeserver: 170.212.24.5
  cmd: "{command_path}/{check_name} -w {warning} -c {critical} -H {timeserver}"

check_users:
  critical: 100
  warning: 50

getPublicIPAddress:
  cmd: "{command_path}/{check_name}"

"""


def icinga_grains():
  grains = yaml.load(g)
  icinga = { 'icinga': { 'Defaults': grains }}

  if (os.path.exists('/etc/redhat-release')):
    icinga['icinga']['Defaults']['default']['command_path'] = '/usr/lib64/nagios/plugins'

  return(icinga)

#print(icinga_grains())
