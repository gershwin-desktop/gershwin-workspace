# Resume: SMB discovery in Workspace (sidebar + /Network)

Branch: `dev` in /Developer/Library/Sources/gershwin-workspace.
WIP commit on `dev` contains: `Workspace/Network/NBNSProbe.{h,m}` (complete),
`Workspace/Network/WSDiscoveryProbe.{h,m}` (**httpPOST incomplete/broken -
must be finished before build**). Foreign untracked files (CloudContextMenu*,
bez2.png, gdbrun3.out) belong to other agents - do not commit them.

## Goal
Show (not mount) SMB/Windows shares in sidebar + /Network, like the existing
zeroconf SSH shares. User fixed the approach:
- NO Avahi shell-outs; use the GNUstep native `NSNetServiceBrowser` (do
  `searchForServicesOfType:@"_smb._tcp." inDomain:@"local."` like sftp).
- plus WS-Discovery and legacy NBNS fallbacks; names via an /etc/hosts-style
  cache; refresh on mDNS didFindService events (AVAHI_BROWSER_NEW), NO timer.

## Verified facts (live LAN 192.168.0.0/24, host MUSIC = 192.168.0.52, MAC
f4:b3:01:72:b1:3b)
- MUSIC advertises `_smb._tcp` via mDNS (hostname music-2.local, port 445) -
  NSNetServiceBrowser path will find it the same way sftp does.
- WS-Discovery: probe XML needs `<d:Types>wsdp:Device</d:Types>` and must be
  sent from source UDP port 3702; answer = ProbeMatch with wsa:Address
  (urn:uuid:...) + wsd:XAddrs (http://192.168.0.52:5357/uuid/).
  Metadata exchange: HTTP POST to XAddr, action
  http://schemas.xmlsoap.org/ws/2004/09/transfer/Get, To=endpoint;
  response has `<pub:Computer>MUSIC/Workgroup:WORKGROUP</pub:Computer>`.
- NBNS: nmblookup '*' broadcast query and broadcast name query for MUSIC are
  silent on this AP; `nmblookup -A 192.168.0.52` (NBSTAT unicast) works.
  - Question name encoding: '*' zero-padded suffix 0x00 = "CK"+"AA"x15;
    real names blank-padded; NBSTAT qtype 0x21 class 1 flags 0x0000;
    broadcast NB query flags 0x0110. NBSTAT response: answer name echoes
    full 32 chars (no pointer), rdata = count + (15B name + 1B type + 2B
    flags)xN + 6B MAC. Real capture fixture saved at
    /tmp/opencode/smb/nbstat.resp (/tmp may be wiped on reboot!).
- LLMNR (224.0.0.252:5355) silent here; implemented as cheap helper anyway.

## Probe scripts (may be lost with /tmp - recreate from this note if needed)
/tmp/opencode/smb/: wsd2.py (working probe, binds 3702), mex.py (metadata),
nbns5.py (NBSTAT + parse), llmnr.py, probe.py.

## Remaining steps
1. Finish `WSDiscoveryProbe.m`: httpPOST (plain socket POST - nonblocking
   connect + select, SO_RCVTIMEO 5s, parse Content-Length, return body) and
   `probeDevicesWithTimeout:` (bind 3702 REUSEADDR fallback ephemeral, send
   4 probes spaced wsdd-style, collect to deadline, parse matches, metadata
   per device, keep only types containing "Computer", return dicts
   {"address", "name", "workgroup", "endpoint"}).
2. New `Workspace/Network/SMBDiscovery.{h,m}`: singleton cache
   (NSUserDefaults key "GWSMBHostCacheV1"; records name/hostname?/address/
   port/lastSeen/misses/workgroup), own worker round:
   WS-D devices + NBNS broadcast IPs -> NBSTAT per candidate IP ->
   refresh cached names via LLMNR + broadcastAddressesForName(name,0x20) ->
   merge into NetworkServiceManager (addManualSMBServiceWithName:address:
   port:hostName:workgroup:) -> save cache. Rounds: startup (~6s sleep in
   detached thread) + rate-limited requestFallbackRefresh (min 45s,
   coalesced); misses decay >=2 when channel had any response.
3. `NetworkServiceManager.{h,m}`: add smbBrowser for `_smb._tcp.`
   (start/stop/SIGABRT-cleanup branches), smbServices accessor,
   addManualSMBServiceWithName:... (merge by name+type via
   existingServiceMatchingName:type: - refactor existingServiceMatchingNetService
   to forward to it - and by address merge), netServiceDidResolveAddress ->
   [SMBDiscovery sharedDiscovery] noteSMBItemResolved:item],
   didFindService _smb -> requestFallbackRefresh, call
   [[SMBDiscovery sharedDiscovery] startupWithServiceManager:self] at end of
   init (ALWAYS, even if NSNetServiceBrowser class missing), stop in
   stopBrowsing. IPv4 sockaddr NSData helper for manual items. Manual item:
   name, type="_smb._tcp.", domain="local.", port 445, resolved=YES,
   netService nil; filter [NBNSProbe isLocalIPv4Address:] before adding.
4. `NetworkServiceItem.{h,m}`: isSMBService (prefix "_smb."), displayName
   "(smb)".
5. `NetworkFSNode.m`: dedupe suffix " (smb)" in subNodes+subNodeNames;
   typeDescription "SMB Server"; openNetworkService SMB branch = alert
   "SMB volume mounting is not yet implemented." (mirror AFP stub).
6. `GWViewerSidebar.m` buildModel (~line 1108): drop the
   `if ([mgr isMDNSAvailable])` gate so fallback-only services show.
7. `Workspace.m goToNetwork:` (~3777): only alert when mDNS unavailable AND
   [manager serviceCount] == 0, else open viewer.
8. `Workspace/GNUmakefile.in` source list (~line 174 block): add
   Network/NBNSProbe.m, Network/WSDiscoveryProbe.m, Network/SMBDiscovery.m.
9. Tests `Tests/Network/`: GNUmakefile.preamble (link source files directly
   like Tests/FSNode does, -lgnustep-gui not needed: Foundation-only);
   t_NBNSProbeParse.m (fixture = real MUSIC NBSTAT 157-byte hex from
   nbstat.resp + firstLevelEncodingForName cases incl. "*" -> "CK"+"AA"x15
   and "MUSIC 0x20" blank-padding), t_WSDProbeParse.m (real ProbeMatches XML
   + real metadata XML fixtures -> endpoint/xaddrs/name/workgroup),
   t_NetworkServiceItemSMB.m (isSMBService/displayName). Red-green loop.
10. clang-format touched files, `make clean && make` zero warnings,
    `gnustep-tests` from repo root, then `sudo make install` (SYSTEM domain
    only) and have the user restart Workspace.
11. Optional/follow-up: smb:// in Connect-to-Server still mounts nothing ->
    leave out for now (show-only milestone); LLMNR/IPv6 formats untested on
    the LAN (silent here).
