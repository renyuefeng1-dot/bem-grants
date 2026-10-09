#!/usr/bin/env bash
# 测试网完整流程脚本：部署 GrantEscrow + 1000 BEM 2-of-3 资助池 + 申请/选定/放款/取消
# 私钥只从环境变量和本地 .testkeys.json 读取，从不打印。
set -euo pipefail
export PATH=$HOME/.foundry/bin:$PATH
cd "$(dirname "$0")/.."
RPC=${RPC:-https://bsc-testnet-rpc.publicnode.com}
BEM=0xAf81078FA7DF6aF5E5bD97B98a358939600EC320
LOG=deploy/testnet-run.log
echo "deploy 0xd5628c87583172a468cc5246b991445e80a76286c76cde4b52b3abd729952b4d escrow=0xcac9A884b1f06d0B7a3CECff81434f748fffdDCF" > $LOG
key(){ python3 -c "import json;print(json.load(open('.testkeys.json'))['data'][$1]['private_key'])"; }
addr(){ python3 -c "import json;print(json.load(open('.testkeys.json'))['data'][$1]['address'])"; }
A1=$(addr 0); A2=$(addr 1); A3=$(addr 2); DEV=$(addr 3)
K1=$(key 0); K2=$(key 1); K3=$(key 2); KD=$(key 3)
CH=97
send(){ # label key to sig args...
  local label=$1 k=$2; shift 2
  local out; out=$(cast send --rpc-url $RPC --chain $CH --legacy --gas-price 1000000000 --private-key "$k" --json "$@")
  local h s; h=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['transactionHash'])")
  s=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['status'])")
  echo "$label $h status=$s" | tee -a $LOG
  [ "$s" = "0x1" ] || [ "$s" = "1" ] || { echo "FAILED: $label"; exit 1; }
}
if [ -z "${ESCROW:-}" ]; then
  out=$(forge create src/GrantEscrow.sol:GrantEscrow --rpc-url $RPC --private-key "$PRIVATE_KEY" --broadcast --legacy --gas-price 1000000000 --json --constructor-args $BEM)
  ESCROW=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['deployedTo'])")
  DH=$(echo "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['transactionHash'])")
  echo "deploy $DH escrow=$ESCROW" | tee -a $LOG
fi
echo "ESCROW=$ESCROW" | tee -a $LOG
# 给 4 个临时钱包各转一点 tBNB 作为 gas
for a in $A1 $A2 $A3 $DEV; do send "fund_gas_$a" "$PRIVATE_KEY" $a --value 0.003ether; done
send approve_bem "$PRIVATE_KEY" $BEM "approve(address,uint256)" $ESCROW 100000000000
URI='{"title":"TapeOut 生态资助池（测试网演示）","desc":"1000 BEM，2-of-3 审批，放款销毁 1%"}'
send createPool_1000BEM_2of3 "$PRIVATE_KEY" $ESCROW "createPool(uint256,string,address[],uint8,uint16)" 100000000000 "$URI" "[$A1,$A2,$A3]" 2 100
DL=$(( $(date +%s) + 14*86400 ))
send createMilestone1_300 "$PRIVATE_KEY" $ESCROW "createMilestone(uint256,uint256,uint64,string,address)" 1 30000000000 $DL '{"title":"BEM 销毁看板（DeWEB 版）","desc":"按应用统计 BEM 销毁"}' 0x0000000000000000000000000000000000000000
send createMilestone2_200 "$PRIVATE_KEY" $ESCROW "createMilestone(uint256,uint256,uint64,string,address)" 1 20000000000 $DL '{"title":"演示：将被取消的里程碑"}' 0x0000000000000000000000000000000000000000
send createMilestone3_100 "$PRIVATE_KEY" $ESCROW "createMilestone(uint256,uint256,uint64,string,address)" 1 10000000000 $DL '{"title":"TapeNow 排错手册英文版","desc":"开放申请中"}' 0x0000000000000000000000000000000000000000
send dev_apply_m1 "$KD" $ESCROW "applyFor(uint256,string)" 1 "https://github.com/renyuefeng1-dot/bem-grants (测试申请)"
send a1_voteAward_m1 "$K1" $ESCROW "voteAward(uint256,uint256)" 1 0
send a2_voteAward_m1 "$K2" $ESCROW "voteAward(uint256,uint256)" 1 0
send dev_submitDelivery_m1 "$KD" $ESCROW "submitDelivery(uint256,string)" 1 "https://renyuefeng1-dot.github.io/bem-grants/ (测试交付)"
B0=$(cast call --rpc-url $RPC $BEM "balanceOf(address)(uint256)" 0x000000000000000000000000000000000000dEaD | awk '{print $1}')
send a1_voteRelease_m1 "$K1" $ESCROW "voteRelease(uint256)" 1
send a3_voteRelease_m1 "$K3" $ESCROW "voteRelease(uint256)" 1
B1=$(cast call --rpc-url $RPC $BEM "balanceOf(address)(uint256)" 0x000000000000000000000000000000000000dEaD | awk '{print $1}')
send a2_voteCancel_m2 "$K2" $ESCROW "voteCancel(uint256)" 2
send a3_voteCancel_m2 "$K3" $ESCROW "voteCancel(uint256)" 2
send dev_apply_m3 "$KD" $ESCROW "applyFor(uint256,string)" 3 "我来做英文版，3 天交付（测试申请）"
echo "dev_balance=$(cast call --rpc-url $RPC $BEM 'balanceOf(address)(uint256)' $DEV)" | tee -a $LOG
echo "dead_delta=$((B1-B0))" | tee -a $LOG
echo "escrow_balance=$(cast call --rpc-url $RPC $BEM 'balanceOf(address)(uint256)' $ESCROW)" | tee -a $LOG
echo "totals(locked,paid,burned)=$(cast call --rpc-url $RPC $ESCROW 'totalLocked()(uint256)') $(cast call --rpc-url $RPC $ESCROW 'totalPaid()(uint256)') $(cast call --rpc-url $RPC $ESCROW 'totalBurned()(uint256)')" | tee -a $LOG
echo "m1_status=$(cast call --rpc-url $RPC $ESCROW 'getMilestone(uint256)((uint256,uint256,uint64,uint8,address,uint8,uint8,string,string))' 1 | cut -c1-200)" | tee -a $LOG
echo "m2_status=$(cast call --rpc-url $RPC $ESCROW 'getMilestone(uint256)((uint256,uint256,uint64,uint8,address,uint8,uint8,string,string))' 2 | cut -c1-120)" | tee -a $LOG
