
;;; This generates the two-byte load-address header for what the xmodem's
;;; doc calls ".o64 format".  See the linker config.
;;; .addr generates 2 bytes.
;;; *+2 means that the value we want here is the address the linker determines
;;; for whatever comes next after this.

.segment "O64HEADER"
.addr *+2
