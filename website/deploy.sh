#!/bin/bash
# Deploy the Narrow Haul site to https://zafrk.com/narrow-haul/
#
# It shares the zafrk.com S3 bucket + CloudFront distribution but only ever
# touches the narrow-haul/ prefix. The zafrk site's own deploy.sh must keep
# `--exclude "narrow-haul/*"` on its `aws s3 sync --delete`, or a zafrk deploy
# would delete these pages.
#
# The site is one self-contained page. CloudFront serves the bucket through an
# S3 REST origin (no index documents, and missing keys fall back to the zafrk
# homepage), so the same page is uploaded under every route's exact key.
#
# Usage: website/deploy.sh            (AWS_PROFILE defaults to my_aws)

set -euo pipefail

PROFILE="${AWS_PROFILE:-my_aws}"
BUCKET="${NH_BUCKET:-zafrk.com}"
REGION="${NH_REGION:-us-east-1}"
DISTRIBUTION="${NH_DISTRIBUTION:-EWUNHC49AUTUQ}"
PREFIX="narrow-haul"
HERE="$(cd "$(dirname "$0")" && pwd)"
PAGE="$HERE/index.html"
PRESS="$HERE/press"

# Every URL the page answers to.
KEYS=(
  "$PREFIX"
  "$PREFIX/"
  "$PREFIX/index.html"
  "$PREFIX/privacy"
  "$PREFIX/support"
  "$PREFIX/press"
)

echo "Deploying $PAGE → s3://$BUCKET/$PREFIX/ (profile $PROFILE)"
for key in "${KEYS[@]}"; do
  # put-object, not `s3 cp`: cp treats a trailing "/" as a folder and would
  # write narrow-haul/index.html instead of the literal "narrow-haul/" key.
  aws s3api put-object \
    --bucket "$BUCKET" \
    --key "$key" \
    --body "$PAGE" \
    --content-type "text/html; charset=utf-8" \
    --cache-control "public, max-age=3600" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --output text --query 'ETag' >/dev/null
  echo "  ✓ /$key"
done

# Press kit files (screenshots, logo, videos, zip) under narrow-haul/press/.
# The mp4s and the zip are gitignored, so build them first on a fresh checkout.
if [ ! -f "$PRESS/narrow-haul-presskit.zip" ]; then
  "$HERE/../tool/store/make_presskit.sh"
fi
for f in "$PRESS"/*; do
  name="$(basename "$f")"
  case "$name" in
    *.jpg) type="image/jpeg" ;;
    *.png) type="image/png" ;;
    *.mp4) type="video/mp4" ;;
    *.zip) type="application/zip" ;;
    *) continue ;;
  esac
  aws s3api put-object \
    --bucket "$BUCKET" \
    --key "$PREFIX/press/$name" \
    --body "$f" \
    --content-type "$type" \
    --cache-control "public, max-age=86400" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --output text --query 'ETag' >/dev/null
  echo "  ✓ /$PREFIX/press/$name"
done

echo "Invalidating /$PREFIX* on CloudFront $DISTRIBUTION"
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION" \
  --paths "/$PREFIX" "/$PREFIX/*" \
  --profile "$PROFILE" \
  --query 'Invalidation.Id' --output text

echo "Done: https://$BUCKET/$PREFIX/  ·  /privacy  ·  /support  ·  /press"
