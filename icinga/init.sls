#!py

import sys
import yaml
import json
import re
import copy
import socket

def expandServiceChecks(ServiceChecks,Defaults):

    ExpandedServiceChecks = {}

    for ServiceName, Check in ServiceChecks.items():
      CheckAttributes = {}

      #
      # check_apt:
      #
      if (not Check):
        CheckName = ServiceName
        CheckAttributes = { 'check_name': CheckName, 'servicename': 'service name only'}

      #
      # myload:
      #   check_load
      #
      if (type(Check) is str):
        CheckName = Check
        CheckAttributes = { 'check_name': CheckName, 'servicename': 'check type is string'}

      if (type(Check) is dict):
        if (ServiceName in Defaults.keys()):
          #
          # check_host:
          #   check_type: active
          # 
          CheckName = ServiceName
          CheckAttributes = Check.copy()
        else:
          #
          # /home:
          #   check_disk:
          #     warning: 20%
          #     critical: 10%
          #
          CheckName = list(Check.keys())[0]
          CheckAttributes = Check[CheckName].copy()


      if (CheckName in Defaults.keys()):
        ServiceCheck = Defaults[CheckName].copy()
      else:
        ServiceCheck = Defaults['default'].copy()

      if ('check_type' in CheckAttributes.keys() and CheckAttributes['check_type'] == 'active'):
        pass
      else:
        ServiceCheck.update(Defaults['passive_check'])

      ServiceCheck.update(CheckAttributes)

      if ('name' in CheckAttributes.keys() and type(CheckAttributes['name']) is list):
        for n in CheckAttributes['name']:
          ExpandedServiceChecks[n] = ServiceCheck.copy()
          ExpandedServiceChecks[n]['check_name'] = CheckName
          ExpandedServiceChecks[n]['name'] = n
      else:
        ServiceCheck['name'] = ServiceName
        ExpandedServiceChecks[re.sub('^check_', '', ServiceName)] = ServiceCheck.copy()

    return(ExpandedServiceChecks)

def run():
    try:
      minion_id = __grains__['id']
    except ValueError:
      minion_id = None

    try:
      p = __pillar__['icinga']
    except ValueError:
      p = {}

    # Expand grains
    try:
      Defaults = __grains__['icinga']['Defaults']
      Default = Defaults['default']
    except ValueError:
      Defaults = Default = {}

    CheckDefaults = {}
    for CheckName, Check in Defaults.items():
        CheckDefaults[CheckName] = {}

        if (not (CheckName in ['passive_check', 'default'])):
          CheckDefaults[CheckName] = Default.copy()
          CheckDefaults[CheckName]['check_name'] = CheckName

        CheckDefaults[CheckName].update(Check)

    try:
      server = __pillar__['icinga-server']
    except (KeyError, ValueError):
      server = {}

    HostConfigs = {}

    for Host, ServiceChecks in p.items():
      ExpandedServiceChecks = expandServiceChecks(ServiceChecks,CheckDefaults)

      msg = ""
      if (server == minion_id):
        # Generate States for establishing icinga checks

        IcingaHostChecks = 'icinga-%s-Checks' % (Host)

        HostCheckType = 'passive'
        FileManaged = []
  
        if ('check_host' in ServiceChecks.keys()):
          HostCheck = ServiceChecks['check_host']

          if ('check_type' in HostCheck.keys() and HostCheck['check_type'] == 'active'):
            HostCheckType = 'active'

  	  if ('ipaddress' in HostCheck.keys()):
            IPAddress = HostCheck['ipaddress']
          else:
            IPAddress = socket.gethostbyname(Host)

          FileManaged.append(
            { 'IPAddress': IPAddress},
          )

        FileManaged.extend([
          { 'Host': Host },
          { 'ServiceChecks': ExpandedServiceChecks.keys() },
          { 'ESC': json.dumps(ExpandedServiceChecks) },
          { 'CD': json.dumps(CheckDefaults) },
          { 'name': '/etc/icinga2/conf.d/ManagedChecks/%s.conf' % (Host) },
          { 'template': 'jinja' },
          { 'source': 'salt://icinga/files/ManagedChecks.jinja' },
          { 'HostCheckType': HostCheckType},
       ])
  
        HostConfigs.update( {
            IcingaHostChecks: { 
            'file.managed': FileManaged
          }
        })

      # Generate cron jobs for passive icinga checks
      if (Host == minion_id):
        for ServiceName, Check in ExpandedServiceChecks.items():
          cmd = "missing cmd"
          if ('cmd' in Check.keys()):
            cmd = Check['cmd']
          if ('options' in Check.keys() and Check['options']):
            cmd += check['options']

          if ('check_type' in Check.keys() and Check['check_type'] == 'passive'):
            CommandToRun = "/usr/local/bin/forwardCheck -s '%s' %s" % (re.sub('^check_', '', Check['name']), cmd.format(**Check))
            StateName = "Icinga-%s-ServiceCheck-%s" % (Host, ServiceName)
            HostConfigs.update( {
              StateName : {
                 'cron.present': [
                   { 'name': CommandToRun },
                   { 'identifier': StateName },
                   { 'user': "%s" % (Check['user'])},
                   { 'minute': "%s" % (Check['minute'])},
                   { 'hour': "%s" % (Check['hour'])},
                   { 'daymonth': "%s" % (Check['dom'])},
                   { 'month': "%s" % (Check['month'])},
                   { 'dayweek': "%s" % (Check['dow'])},
                 ]
              }
            })

    return( HostConfigs )

