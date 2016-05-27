#  ===================================================================
#  Embedded Syslog Manager                           ||        ||
#                                                    ||        ||
#  Filter out messages about 169.254.0.0/16 IP addresses 
#  ====================================================================
#
# Namespace: global
#
# Example configuration :
#  logging filter flash:MessageFilter.tcl 
#  logging host 192.168.1.1 filtered 
#
# http://www.cisco.com/c/en/us/td/docs/ios/netmgmt/configuration/guide/12_2sx/nm_12_2sx_book/nm_esm_syslog.html
#

# Check for null message

if { [string length $::orig_msg] == 0} {
   return ""
}
 
if { [regexp -all {169\.254\.} $::orig_msg] > 0 } {
    return ""
}

return $::orig_msg 
 