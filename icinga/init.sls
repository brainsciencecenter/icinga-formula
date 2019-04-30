#!py

import sys
import yaml
import json
import re
import copy
import socket

def expandServiceChecks(ServiceChecks,Defaults):
    debug = 1

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
      if (debug):
        print("'%s' : '%s' : CheckType = %s" % (ServiceName, Check, type(Check)))
      if (type(Check) is str or type(Check) is unicode):
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


      ServiceCheck = Defaults['default'].copy()

      if ('check_type' in CheckAttributes.keys() and CheckAttributes['check_type'] == 'active'):
        pass
      else:
        ServiceCheck.update(Defaults['passive_check'])

      if (CheckName in Defaults.keys()):
        ServiceCheck.update(Defaults[CheckName])
        if (debug):
          print("CheckName in Defaults.keys: '%s' in %s" % (CheckName, ','.join(Defaults.keys())))

      if (debug):
        print("ServiceCheck: ",ServiceCheck)

      ServiceCheck.update(CheckAttributes)
      if (debug):
        print("ServiceCheck.update(CheckAttributes): ", ServiceCheck)

      if ('name' in CheckAttributes.keys() and type(CheckAttributes['name']) is list):
        for n in CheckAttributes['name']:
          ExpandedServiceChecks[n] = ServiceCheck.copy()
          ExpandedServiceChecks[n]['check_name'] = CheckName
          ExpandedServiceChecks[n]['name'] = n
      else:
        ServiceCheck['name'] = ServiceName
        if (not ('check_name' in ServiceCheck.keys())):
          ServiceCheck['check_name'] = CheckName
        ExpandedServiceChecks[re.sub('^check_', '', ServiceName)] = ServiceCheck.copy()

    return(ExpandedServiceChecks)

def run():
    global __grains__
    global __pillar__

    debug = 1

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

    #
    # Sometimes you need a host to do active checks
    # bfb-checks:
    #   ....
    # hippogang-nas-checks:
    #   ....
    #

    if (debug):
      print("CheckDefaults: ",CheckDefaults)

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

      # Copy in the nagios plugins and supporting scripts
      if ('icinga-files' in __pillar__.keys()):
        for File in __pillar__['icinga-files']:
          HostConfigs.update( {
            File : {
              'file.managed' : [
                { 'source' : 'salt://files%s' % (File) },
                { 'user' : 'root' },
                { 'group' : 'root' },
                { 'mode' : '755' },
              ]
            }
          })


      if ('packages' in __pillar__.keys() and 'nagiosplugins' in __pillar__['packages'].keys()):
        HostConfigs.update( {
  
          'nagios-plugins' : {
            'pkg.installed' : [
              { 'pkgs' : __pillar__['packages']['nagiosplugins']},
            ]
          },
  
        })

      # Generate cron jobs for passive icinga checks
      if (Host == minion_id):
        # Add host check
        CommandToRun = "/usr/local/bin/forwardCheck -H %s" % (Host)
        StateName = "Icinga-%s-HostCheck" % (Host)
        HostConfigs.update( {
          StateName : {
            'cron.present' : [
              { 'name' : CommandToRun },
              { 'identifier': StateName },
              { 'user': "%s" % ('root')},
              { 'minute': "%s" % ( '*/5' )},
              { 'hour': "%s" % ( '*' )},
              { 'daymonth': "%s" % ( '*' )},
              { 'month': "%s" % ( '*' )},
              { 'dayweek': "%s" % ( '*' )},
            ]
          }
        })

        for ServiceName, Check in ExpandedServiceChecks.items():
          if (debug):
            print("'%s' : '%s'" % (json.dumps(ServiceName), json.dumps(Check)))
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

def main():
  global __pillar__
  global __grains__

  # Create /tmp/pillar and /tmp/grains with
  # salt --out=json compute-1-6.chead.uphs.upenn.edu grains.items  > /tmp/grains
  # salt --out=json compute-1-6.chead.uphs.upenn.edu pillar.items  > /tmp/pillar

  with open('/tmp/pillar') as json_file:  
    pillar = json.load(json_file)
  __pillar__ = pillar
  __pillar__ = pillar['compute-1-6.chead.uphs.upenn.edu']

  with open('/tmp/grains') as json_file:  
    grains = json.load(json_file)
  __grains__ = grains['compute-1-6.chead.uphs.upenn.edu']

  run()
  
if __name__== "__main__":
  main()
