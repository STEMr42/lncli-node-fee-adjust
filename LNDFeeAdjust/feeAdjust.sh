#!/usr/bin/env bash

##########################################################
#   LN fee policy update for multi-node setup
#   -Requires LNCLI, JQ, BC
#   -Requires macaroon, rpc server address, tls cert for each root node
#   -Set individual policy for Root node interlinks, LSPs (preffered rate partners),
#       Leaf nodes (single peer), and default for others
#########################################################

#get configs
rootNodes=$(cat rootnodes.json)
echo "rootNodes --->" 
echo $(jq -r '.nodes[].name' <<< ${rootNodes[@]})
lspNodes=$(cat lspnodes.json)
echo "lspNodes --->"
echo $(jq -r '.nodes[].name' <<< ${lspNodes[@]})
rootNodeRate=$(cat rates.json | jq -r '.rates.root')
echo "rootNodeRate = $rootNodeRate"
rootNodeppm=$( bc <<< "$rootNodeRate*1000000/1" )
echo "rootNodeppm = $rootNodeppm"
lspNodeRate=$(cat rates.json | jq -r '.rates.lsp')
echo "lspNodeRate = $lspNodeRate"
lspNodeppm=$( bc <<< "$lspNodeRate*1000000/1" )
echo "lspNodeppm = $lspNodeppm"
leafNodeRate=$(cat rates.json | jq -r '.rates.leaf')
echo "leafNodeRate = $leafNodeRate"
leafNodeppm=$( bc <<< "$leafNodeRate*1000000/1" )
echo "leafNodeppm = $leafNodeppm"
otherNodeRate=$(cat rates.json | jq -r '.rates.other')
echo "otherNodeRate = $otherNodeRate"
otherNodeppm=$( bc <<< "$otherNodeRate*1000000/1" )
echo "otherNodeppm = $otherNodeppm"
baseFee=$(cat rates.json | jq -r '.rates.base')
echo "baseFee = $baseFee"

# --base_fee_msat value  the base fee in milli-satoshis that will be charged for each forwarded HTLC, regardless of payment size
# --fee_rate value  the fee rate that will be charged proportionally based on the value of each forwarded HTLC, 
#       the lowest possible rate is 0 with a granularity of 0.000001 (millionths)

#loop through root nodes
for node in $(jq '.nodes | keys | .[]' <<< ${rootNodes[@]}); do
    echo ""
    echo "**** starting new node ****"
    data=$(jq -r ".nodes[$node]" <<< ${rootNodes[@]});
    numRootNodes=$(jq -r '.nodes | length' <<< ${rootNodes[@]})
    echo "numRootNodes = $numRootNodes"    
    name=$(jq -r '.name' <<< $data);
    echo "name = $name"
    pubKey=$(jq -r '.pub_key' <<< $data);
    echo "pubkey = $pubKey"
    socket=$(jq -r '.rpcserver' <<< $data);
    echo "socket = $socket"
    macaroonpath=$(jq -r '.macaroon_path' <<< $data);
    echo "macaroon path = $macaroonpath"
    tlscertpath=$(jq -r '.tlscert_path' <<< $data);
    echo "tlscert path = $tlscertpath"
    
    #get channel list - try again on lncli error
    while [ true ]; do
    chanData=$(lncli --rpcserver $socket --macaroonpath $macaroonpath --tlscertpath $tlscertpath listchannels)
    if [ -n "$chanData" ]; then break; fi
    echo "LNCLI ERROR - WAIT 3s"
    sleep 3
    done
    numChannels=$(jq -r '.channels | length' <<< ${chanData[@]})
    echo "numChannels = $numChannels"

    #get feereport - try again on lncli error
    while [ true ]; do
        feeData=$(lncli --rpcserver $socket --macaroonpath $macaroonpath --tlscertpath $tlscertpath feereport)
        if [ -n "$feeData" ]; then break; fi
            echo "LNCLI ERROR - WAIT 3s"
        sleep 3
    done  
    echo "num fee data = $(jq -r '.channel_fees | length' <<< ${feeData[@]})"
    #echo $(jq '.channel_fees' <<< ${feeData[@]})
      
    #loop through channels
    for channel in $(jq '.channels | keys | .[]' <<< ${chanData[@]}); do
            echo "**********************************************************************************************"
            echo "root node $((node + 1)) / $numRootNodes"
            echo "channel $((channel + 1)) / $numChannels"
            data=$(jq -r ".channels[$channel]" <<< ${chanData[@]});
            remotePubkey=$(jq -r '.remote_pubkey' <<< $data)
            chanID=$(jq -r '.chan_id' <<< $data)
            chanPoint=$(jq -r '.channel_point' <<< $data)
            chFees=$(jq -r --arg chanID "$chanID" '.channel_fees[] | select(.chan_id == $chanID)' <<< ${feeData[@]})
            #echo "chFees = $chFees"
            bFee=$(jq -r '.base_fee_msat' <<< ${chFees[@]})
            rFee=$(jq -r '.fee_per_mil' <<< ${chFees[@]})
            #get node info for current remote pub key
            while [ true ]; do
                peerNodeData=$(lncli --rpcserver $socket --macaroonpath $macaroonpath --tlscertpath $tlscertpath getnodeinfo --pub_key $remotePubkey)
                if [ -n "$peerNodeData" ]; then break; fi
                echo "LNCLI ERROR - WAIT 3s"
                sleep 3           
            done
            peerAlias=$(jq '.node.alias' <<< ${peerNodeData[@]})
            echo "peerAlias = $peerAlias"           
            echo "remotePubkey = $remotePubkey"
            echo "chanID = $chanID"
            echo "chanPoint = $chanPoint"
            echo "bFee = $bFee"
            echo "rFee = $rFee"             

            #look for root node
            check=$(jq -r --arg remotePubkey "$remotePubkey" '.nodes[] | select(.pub_key == $remotePubkey)' <<< ${rootNodes[@]})
            #echo $check
            if [ -n "$check" ]; then #found root node
                echo "found ROOT node"
                #if fees not set right, updatepolicy
                echo "rate check"
                if [[ $bFee != $baseFee || $rFee != $rootNodeppm ]]; then
                    echo "setting root node fee $baseFee base $rootNodeRate rate"
 #comment this out for testing
            while [ true ]; do
                error=$(lncli --rpcserver $socket --macaroonpath $macaroonpath --tlscertpath $tlscertpath updatechanpolicy \
                --time_lock_delta 40 --base_fee_msat 0 --fee_rate $rootNodeRate --chan_point $chanPoint 2>&1 > /dev/null)
                if [ -z "$error" ]; then break; fi
                echo "LNCLI ERROR - WAIT 3s"
                sleep 3
            done
 ################################
                else
                    echo "fee match"
                fi #finished fee check
                continue #finished root node check, move to next channel
            fi #finished root node check
    echo "NOT root"
            #look for lsp node
            check=$(jq -r --arg remotePubkey "$remotePubkey" '.nodes[] | select(.pub_key == $remotePubkey)' <<< ${lspNodes[@]})
            #echo $check
            if [ -n "$check" ]; then #found LSP node
                echo "found LSP node"
                #if fees not set right, updatepolicy
                echo "rate check"
                if [[ $bFee != $baseFee || $rFee != $lspNodeppm ]]; then
                    echo "setting LSP node fee $baseFee base $lspNodeRate rate"
 #comment this out for testing
            while [ true ]; do
                error=$(lncli --rpcserver $socket --macaroonpath $macaroonpath --tlscertpath $tlscertpath updatechanpolicy \
                --time_lock_delta 40 --base_fee_msat 0 --fee_rate $lspNodeRate --chan_point $chanPoint 2>&1 > /dev/null)
                if [ -z "$error" ]; then break; fi
                echo "LNCLI ERROR - WAIT 3s"
                sleep 3
            done
 ###############################
                 else
                    echo "fee match"
                fi #finished fee check
                continue #finished root node check, move to next channel
            fi #finished lsp node check
    echo "NOT lsp"
 #comment this out to skip leaf node - this check requires the most time
            #look for leaf node (single peer only!)
            peerNumChannels=$(jq '.num_channels' <<< ${peerNodeData[@]})
            echo "peerNumChannels = $peerNumChannels"
            #get peer num channels w/ root node
            nodeNumChannels=$(jq -r --arg remotePubkey "$remotePubkey" '[.channels[].remote_pubkey | select(. == $remotePubkey)] | length' <<< ${chanData[@]});
            echo "nodeNumChannels = $nodeNumChannels"

            #If peer num channels == our node num channels to peer, consider leaf node - these are sngle peer nodes that can't forward
            if [ $peerNumChannels -eq $nodeNumChannels ]; then #found leaf node
                echo "found LEAF node"
                #if not set right, updatepolicy
                echo "rate check"
                testv=0
                if [[ $bFee != $baseFee || $rFee != $leafNodeppm ]]; then
                    echo "setting leaf node fee $baseFee base $leafNodeRate rate"
 #comment this out for testing
            while [ true ]; do
                error=$(lncli --rpcserver $socket --macaroonpath $macaroonpath --tlscertpath $tlscertpath updatechanpolicy \
                --time_lock_delta 40 --base_fee_msat 0 --fee_rate $leafNodeRate --chan_point $chanPoint 2>&1 > /dev/null)
                if [ -z "$error" ]; then break; fi
                echo "LNCLI ERROR - WAIT 3s"
                sleep 3
            done
 ###############################
                else
                    echo "fee match"
                fi #finished fee check
                continue #finished root node check, move to next channel
            fi #finished single channel check
    echo "NOT leaf"
############################################################################## end leaf node
            #no matches found, set other node rate
            echo "found OTHER node"
            echo "rate check"
            #if fees not set right, updatepolicy
            if [[ $bFee != $baseFee || $rFee != $otherNodeppm ]]; then
                echo "setting other node fee $baseFee base $otherNodeRate rate"
#comment this out for testing
            while [ true ]; do
                error=$(lncli --rpcserver $socket --macaroonpath $macaroonpath --tlscertpath $tlscertpath updatechanpolicy \
                --time_lock_delta 40 --base_fee_msat 0 --fee_rate $otherNodeRate --chan_point $chanPoint 2>&1 > /dev/null)
                if [ -z "$error" ]; then break; fi
                echo "LNCLI ERROR - WAIT 3s"
                sleep 3
            done
###############################
                 else
                    echo "fee match"
                fi #finished fee check
            
    done #finished channel loop
done #finished node loop
