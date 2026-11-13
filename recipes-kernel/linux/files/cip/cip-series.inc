# CIP folders, applied in this order
CIP_BATCHES = " \
    v6.12.43-cip7 \
    v6.12.46-cip8 \
    v6.12.48-cip9 \
    v6.12.51-cip10 \
    v6.12.55-cip11 \
    v6.12.57-cip12 \
    v6.12.57-cip13 \
    v6.12.59-cip14 \
    v6.12.63-cip15 \
    v6.12.66-cip16 \
    v6.12.69-cip17 \
    v6.12.76-cip18 \
    v6.12.78-cip19 \
    v6.12.80-cip20 \
    v6.12.83-cip21 \
    v6.12.85-cip22 \
    v6.12.88-cip23 \
    v6.12.90-cip24 \
    v6.12.92-cip25 \
    v6.12.94-cip26 \
    v6.12.95-cip27 \
    v6.12.96-cip28 \
    v6.12.101-cip29 \
    v6.12.104-cip30 \
    v6.12.108-cip31 \
    v6.12.111-cip32 \
    v6.12.112-cip33 \
"
# Stable version of the last folder
LINUX_VERSION:j722s-ecu1270 = "6.12.112"
# meta-ti sets PV, not LINUX_VERSION; keep PV in step with the CIP stable version
PV:j722s-ecu1270 = "${LINUX_VERSION}+git"
