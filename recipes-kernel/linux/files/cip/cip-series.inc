# CIP folders, applied in this order
CIP_BATCHES = " \
    v6.12.43-cip7 \
    v6.12.46-cip8 \
    v6.12.48-cip9 \
    v6.12.51-cip10 \
    v6.12.55-cip11 \
    v6.12.57-cip12 \
"
# Stable version of the last folder
LINUX_VERSION:j722s-ecu1270 = "6.12.57"
# meta-ti sets PV, not LINUX_VERSION; keep PV in step with the CIP stable version
PV:j722s-ecu1270 = "${LINUX_VERSION}+git"
