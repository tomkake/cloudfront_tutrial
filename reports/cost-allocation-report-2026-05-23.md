# Cost Allocation Report

## 概要

CloudFront distribution を `CostProject=projectA` / `CostProject=projectB` タグで分類し、共有 Lambda のコストを CloudWatch Logs Insights の `viewer_host` 集計で概算按分するための確認レポートです。

確認日時: 2026-05-23
対象期間: 2026-05-01 から 2026-05-24 まで
Cost Explorer の期間指定では終了日は排他的に扱われます。

## Project と CloudFront の対応

| Project | CloudFront distribution ID | Domain | Tag |
| --- | --- | --- | --- |
| `projectA` | `PROJECTA_DISTRIBUTION_ID` | `projectA-distribution.cloudfront.net` | `CostProject=projectA` |
| `projectB` | `PROJECTB_DISTRIBUTION_ID` | `projectB-distribution.cloudfront.net` | `CostProject=projectB` |

## 実行した Cost Explorer コマンド

サービス別の Lambda / CloudFront コスト:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-05-24 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["AWS Lambda","Amazon CloudFront"]}}'
```

CloudFront を `CostProject` タグで group by:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-05-24 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=TAG,Key=CostProject \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon CloudFront"]}}'
```

## Cost Explorer 結果

| Service | UnblendedCost | Unit | Estimated |
| --- | ---: | --- | --- |
| AWS Lambda | 0 | USD | true |
| Amazon CloudFront | 0 | USD | true |

`CostProject` タグ別 CloudFront コスト:

| Tag group | UnblendedCost | Unit | Estimated |
| --- | ---: | --- | --- |
| `CostProject$` | 0 | USD | true |

`CostProject$` はタグ値なしのグループを示します。現時点では CloudFront コストが 0 USD のため、projectA / projectB のタグ別実額は Cost Explorer 上ではまだ確認できません。
タグを Cost Explorer で使うには、AWS Billing 側で `CostProject` をコスト配分タグとして有効化する必要があります。有効化後も Cost Explorer への反映には時間がかかることがあります。

## Logs Insights による Lambda 按分率

直近 24 時間の Lambda ログを対象に、`viewer_host` を projectA / projectB に変換して集計しました。

| Metric | Value |
| --- | ---: |
| `total_invocations` | 9 |
| `projectA_invocations` | 5 |
| `projectA_percent` | 55.5556 |
| `projectB_invocations` | 4 |
| `projectB_percent` | 44.4444 |
| `unknown_invocations` | 0 |
| `unknown_percent` | 0 |

## 概算料金

現時点で Cost Explorer の Lambda 総コストが 0 USD のため、按分後の Lambda 概算料金も 0 USD です。

| Project | CloudFront cost | Lambda allocation ratio | Allocated Lambda cost | Approx total |
| --- | ---: | ---: | ---: | ---: |
| `projectA` | 0 USD | 55.5556% | 0 USD | 0 USD |
| `projectB` | 0 USD | 44.4444% | 0 USD | 0 USD |

実コストが出た後の計算式:

```text
projectA Lambda cost = Lambda total cost x 55.5556 / 100
projectB Lambda cost = Lambda total cost x 44.4444 / 100
```

## 判断

料金レポートは出せます。ただし、今回の確認時点では Cost Explorer 側の Lambda / CloudFront 実額が 0 USD だったため、実額ベースの配賦結果も 0 USD です。

一方で、Logs Insights による projectA / projectB の按分率は取得できています。実額が Cost Explorer に反映されれば、この比率を使って shared Lambda の料金を projectA / projectB に概算配賦できます。
