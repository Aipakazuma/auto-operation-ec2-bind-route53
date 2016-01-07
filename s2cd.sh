# @name        s2cd
# @description automatic start ec2 instance and route53 chanage host a record
# @version     0.1.0
# @date        2016/01/07
# @auther      aipa
#
# @usage
# $1 - option start / stop
# 
#!/bin/bash
#################################################

# 引数チェック
if [ ! $# -eq 1 ]; then
  echo "Error: args."
fi

# ドメイン
HOST_NAME=""   # 任意の設定するホスト名
DOMAIN_NAME="" # 任意設定するドメイン名
# 検索ec2タグ
EC2_TAG=""
EC2_VALUE=""
# 第一引数のStringチェック
COMMAND="$1"
EC2_COMMAND=""
START_CONTINUE=""
STOP_CONTINUE=""
if [ ${COMMAND} == "start" ]; then
  EC2_COMMAND="start-instances"
  START_CONTINUE="break"
elif [ ${COMMAND} == "stop" ]; then
  EC2_COMMAND="stop-instances"
  STOP_CONTINUE="break"
else
  echo "Error: input start or stop."
  exit 1
fi

# 対象のインスタンスIDを取得する
INSTANCE_ID=`aws ec2 describe-instances --filter Name=tag-key,Values=${EC2_TAG}  Name=tag-value,Values=${EC2_VALUE} | jq '.Reservations[].Instances[].InstanceId' | sed -e "s/\"//g"`

# 処理を実行
aws ec2 ${EC2_COMMAND} --region=ap-northeast-1 --instance-ids=${INSTANCE_ID} >/dev/null 2>&1

# ステータスを確認する
# 起動なら値は入っている（はず）
# 停止なら0
while :
do
  # 10秒待機
  sleep 10
  INSTANCE_STATUS=`aws ec2 describe-instance-status --region=ap-northeast-1 --instance-ids=${INSTANCE_ID} | jq -r '.InstanceStatuses[]'`

  # 空っぽなら停止
  if [ -z "${INSTANCE_STATUS}" ]; then
    echo "status stop"
    eval ${STOP_CONTINUE}
  else
    echo "status running"
    eval ${START_CONTINUE}
  fi
done

# 起動の処理なら、次に動的にドメインを設定する
if [ ${COMMAND} == "start" ]; then
    IP_ADDRESS=`aws ec2 describe-instances --filter Name=tag-key,Values=${EC2_TAG} Name=tag-value,Values=${EC2_VALUE} | jq -r '.Reservations[].Instances[].PublicIpAddress'`
    HOST_ID=`aws route53 list-hosted-zones-by-name --dns-name ${DOMAIN_NAME} | jq -r '.HostedZones[].Id' | awk -F '/' '{print $3}'`
    # requestするjsonを作成
    BATCH_JSON='{
      "Changes": [
        { "Action": "UPSERT",
          "ResourceRecordSet": {
            "Name": "'${HOST_NAME}'.'${DOMAIN_NAME}'",
            "Type": "A",
            "TTL" : 60,
            "ResourceRecords": [
              { "Value": "'${IP_ADDRESS}'" }
            ]
          }
        }
      ]
    }'

    # route53へリクエスト
    aws route53 change-resource-record-sets --hosted-zone-id ${HOST_ID} --change-batch "${BATCH_JSON}" >/dev/null 2>&1
fi

