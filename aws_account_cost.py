import boto3
from datetime import date, timedelta

USD_TO_INR = 95.8
GST_PERCENT = 0.18

client = boto3.client('ce', region_name='us-east-1')

start = date.today().replace(day=1).strftime('%Y-%m-%d')
end = (date.today() + timedelta(days=1)).strftime('%Y-%m-%d')

response = client.get_cost_and_usage(
    TimePeriod={
        'Start': start,
        'End': end
    },
    Granularity='MONTHLY',
    Metrics=['UnblendedCost']
)

usd_amount = float(
    response['ResultsByTime'][0]['Total']['UnblendedCost']['Amount']
)

inr_amount = usd_amount * USD_TO_INR
gst_amount = inr_amount * GST_PERCENT
final_amount = inr_amount + gst_amount

print("=" * 50)
print("AWS BILL SUMMARY")
print("=" * 50)
print(f"USD Cost        : ${usd_amount:.2f}")
print(f"INR Cost        : ₹{inr_amount:.2f}")
print(f"GST (18%)       : ₹{gst_amount:.2f}")
print(f"Final Amount    : ₹{final_amount:.2f}")
print("=" * 50)
