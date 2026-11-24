# CDN assets (cz-css-1010)
Assets extracted from inline base64 data URIs in CSS. Upload to S3 and serve via CloudFront:

    aws s3 sync cdn-assets/img s3://${CDN_BUCKET}/img --cache-control "public,max-age=31536000,immutable"

CSS references https://cdn.northwind.io/img/... (the CloudFront distribution domain; adjust to your distribution/alias).
