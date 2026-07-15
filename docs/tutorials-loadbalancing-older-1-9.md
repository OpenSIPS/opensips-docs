---
title: Load Balancing
description: This tutorial applies for OpenSIPS versions 1.5, 1.6, 1.7 .
---
## Load Balancing in **OpenSIPS**

The "load-balancing" module comes to provide traffic routing based on load. Shortly, when **OpenSIPS** routes calls to a set of destinations, it is able to keep the load status (as number of ongoing calls) of each destination and to choose to route to the less loaded destination (at that moment).
**OpenSIPS** is aware of the capacity of each destination - it is preconfigured with the maximum load accepted by the destinations. To be more precise, when routing, **OpenSIPS** will consider the less loaded destination not the destination with the smallest number of ongoing calls, but the destination with the largest available slot.

Also, the **[load-balancing](/modules/devel/load_balancer)** (LB) module is able to receive feedback from the destinations (if they are capable of). This mechanism is used for notifying **OpenSIPS** when the maximum capacity of a destination changed (like a GW with more or less E1 cards).

The "load-balancing" functionality comes to enhance the "dispatcher" one. The difference comes in having or not load information about the destinations where you are routing to:

* **Dispatcher has no load information** - it just blindly forwards calls to the destinations based on a probabilistic dispersion logic. It gets no feedback about the load of the destination (like how many calls that were sent actually were established or how many are still going).
* **Load-balancer is load driven** - LB routing logic is based primary on the load information. The LB module is using the DIALOG module in order to keep trace of the load (ongoing calls).

- - -

## Load Balancing - how it works

When looking at the LB implementation in **OpenSIPS**, we have 3 aspects:

### Destination set

A destination is defined by its address (a SIP URI) and its description as capacity.

Form the LB module perspective, the **destinations are not homogeneous** - they are not alike; and not only from capacity point of view, but also from what kind of **services/resources** they offer. For example, you may have a set of Yate/Asterisk boxes for media-related services -some of them are doing transcoding, other voicemail or conference,  other simple announcement , other PSTN termination. But you may have mixed boxes - one box may do PSTN and voicemail in the same time. So each destination from the set may offer a different set of services/resources.

So, for each destination, the LB module defines the offered resources, and for each resource, it defines the **capacity / maximum load** as number of concurrent calls the destination can handle for that resource.

Example:

```text
4 destinations/boxes in the LB set
    1) offers 30 channels for transcoding and 32 for PSTN
    2) offers 100 voicemail channels and 10 for transcoding
    3) offers 50 voicemail channels and 300 for conference
    4) offers 10 voicemail, 10 conference, 10 transcoding and 32 PSTN

This translated into the following setup:

+----+----------+--------------------------+---------------------------------+
| id | group_id | dst_uri                  | resources                       |
+----+----------+--------------------------+---------------------------------+
|  1 |        1 | sip:media1.mycluster.net | transc=30; pstn=32              |
|  2 |        1 | sip:media2.mycluster.net | vm=100; transc=10               |
|  3 |        1 | sip:media3.mycluster.net | vm=50; conf=300                 |
|  4 |        1 | sip:media4.mycluster.net | vm=10;conf=10;transc=10;pstn=32 |
+----+----------+--------------------------+---------------------------------+
```

For runtime, the LB module provides MI commands for:

* reloading the definition of destination sets
* changing the capacity for a resource for a destination

### Invoking Load-balancing

Using the LB functionality is very simple - you just have to pass to the LB module what kind of resources the call requires.

The resource detection is done in the **OpenSIPS** routing script, based on whatever information is appropriated. For example, looking at the RURI (dialed number) you can see if the call must go to PSTN or if it a voicemail or conference number; also, by looking at the codecs advertised in the SDP, you can figure out if transcoding is or not also required.

```opensips
  if (!lb_start( 1, "transc;pstn")) {
      sl_send_reply( 500,"Service full");
      exit;
  }
```

The first parameter of the function identifies the LB set to be used (see the group_id column in the above DB snapshot). Second parameter is list of the required resource for the call.

The **load_balance()** will automatically create the dialog state for the call (in order to monitor it) and will also allocate the requested resources for it (from the selected box).  

The function will set as destination URI (`$du`) the address of the selected destination/box.

The resources will be automatically released when the call terminates. 

The LB module provides an MI function that allows the admin to inspect the current load over the destinations.

### The LB logic

The logic used by the LB module to select the destination is:

* gets the **destination set based on the group_id** (first parameter of the *load_balance()* function)
* selects from the set only the **destinations that are able to provide the requested resources** (second parameter of the *load_balance()* function)
* for the selected destinations, it **evaluated the current load** for each requested resource
* the winning destination is the one with **the biggest value for the minimum available load** per resources.

```text
Example:

4 destinations/boxes in the LB set
    1) offers 30 channels for transcoding and 32 for PSTN
    2) offers 100 voicemail channels and 10 for transcoding
    3) offers 50 voicemail channels and 300 for conference
    4) offers 10 voicemail, 10 conference, 10 transcoding and 32 PSTN

when calling load_balance(1,"transc;pstn") ->

1) only boxes (1) and (4) will be selected at as they offer both transcoding and pstn

2) evaluating the load  :
    (1) transcoding - 10 channels used; PSTN - 18 used 
    (4) transcoding - 9 channels used; PSTN - 16 used 

   evaluating available load (capacity-load) :
    (1) transcoding - 20 channels used; PSTN - 14 used 
    (4) transcoding - 1 channels used; PSTN - 16 used 

3) for each box, the minimum available load (through all resources)
    (1) 14 (PSTN)
    (2) 1 (transcoding) 

4) final selected box in (1) as it has the the biggest (=14) available load for the most loaded resource.
```

The selection algorithm tries to avoid the intensive usage of a resource per box.

- - -

## Study Case: routing the media gateways

Here is the full configuration and script for performing LB between media peers.

### Configuration

Let's consider the case previously described:

```text
4 destinations/boxes in the LB set
    1) offers 30 channels for transcoding and 32 for PSTN
    2) offers 100 voicemail channels and 10 for transcoding
    3) offers 50 voicemail channels and 300 for conference
    4) offers 10 voicemail, 10 conference, 10 transcoding and 32 PSTN

This translated into the following setup:

+----+----------+--------------------------+---------------------------------+
| id | group_id | dst_uri                  | resources                       |
+----+----------+--------------------------+---------------------------------+
|  1 |        1 | sip:media1.mycluster.net | transc=30; pstn=32              |
|  2 |        1 | sip:media2.mycluster.net | vm=100; transc=10               |
|  3 |        1 | sip:media3.mycluster.net | vm=50; conf=300                 |
|  4 |        1 | sip:media4.mycluster.net | vm=10;conf=10;transc=10;pstn=32 |
+----+----------+--------------------------+---------------------------------+
```

### OpenSIPS Scripting

The**[ full config file is here](<https://github.com/OpenSIPS/opensips/tree/master/modules/load_balancer/samples/opensips-load-balancer.cfg
>)**, doing load balancing for the INVITEs, with failover to another destination if 5xx is received or upon timeout (no reply) from destination.
