# LND-Node-Fee-Adjust

***Multi node fee adjust bash script using lncli***

Root nodes (generally 0 base / 0 ppm) - interconnected root routing nodes.  Required macaroon with get and peer change permissions.

LSP nodes (generally a preferred rate) - selected routing partners.
  
Leaf nodes - attached nodes that cannot route, their only peer is a single root node.
  
Other nodes (generally highest rates) - all remaining nodes.

***Rates are NOT in ppm, %, or basis points***

 --base_fee_msat value  the base fee in milli-satoshis that will be charged for each forwarded HTLC, regardless of payment size (default: 0)
 
 --fee_rate value  the fee rate that will be charged proportionally based on the value of each forwarded HTLC, 
       the lowest possible rate is 0 with a granularity of 0.000001 (millionths)

# Installation

Download script and json templates. Install in the same directory. Setup and validate the json configs.

# Requirements

lnd (backend connection not required, just lncli), bash, jq, bc

# Running

```
chmod +x feeAdjust.sh
./feeAdjust.sh
```

Comment out lncli blocks for test run
   


