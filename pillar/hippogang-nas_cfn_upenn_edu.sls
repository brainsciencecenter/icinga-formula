#
# - service_name:
#     check_name:
#       attribute1
#       attribute2
#       attribute3
#
# Watch out for the missing colon after check_name here
# - service name:
#     check_name
#
# - check_name:
#
# - check_name:
#     attribute1
#     attribute2
#
# name => icinga service name
# tag  => salt stanza name
#
#

icinga:
  hippogang-nas.uphs.upenn.edu:
    check_host:
      check_type: active

    web:
      check_http:
        name: hippogang-nas
        port: 5000  
