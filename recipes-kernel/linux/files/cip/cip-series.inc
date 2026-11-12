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
"
# Stable version of the last folder
LINUX_VERSION:j722s-ecu1270 = "6.12.80"
# meta-ti sets PV, not LINUX_VERSION; keep PV in step with the CIP stable version
PV:j722s-ecu1270 = "${LINUX_VERSION}+git"
