# ``MoQTHaishinKit``
This module supports the MoQT protocol.

@Metadata {
    @PageImage(purpose: icon, source: "moqthaishinkit-icon.svg", alt: "Media relay over QUIC")
    @PageImage(purpose: card, source: "moqthaishinkit-card.svg", alt: "Media relay over QUIC")
}

## Overview
- This is a Swift implementation of MoQT, based on draft7. It is being developed for research and testing purposes.
- The features for live streaming and viewing have not been implemented yet, so testing is not possible at this time.

## Control Messages
- [x] 6.2. CLIENT_SETUP
- [x] 6.2. SERVER_SETUP
- [ ] 6.3. GOAWAY
- [x] 6.4. SUBSCRIBE
- [x] 6.5. SUBSCRIBE_UPDATE
- [ ] 6.6. UNSUBSCRIBE
- [ ] 6.7. FETCH
- [ ] 6.8. FETCH_CANCEL
- [x] 6.9. ANNOUNCE_OK
- [x] 6.10. ANNOUNCE_ERROR
- [ ] 6.11. ANNOUNCE_CANCEL
- [ ] 6.12. TRACK_STATUS_REQUEST 
- [ ] 6.13. SUBSCRIBE_ANNOUNCES 
- [ ] 6.14. UNSUBSCRIBE_ANNOUNCES
- [x] 6.15. SUBSCRIBE_OK
- [x] 6.16. SUBSCRIBE_ERROR
- [ ] 6.17. FETCH_OK
- [ ] 6.18. FETCH_ERROR
- [ ] 6.19. SUBSCRIBE_DONE
- [ ] 6.20. MAX_SUBSCRIBE_ID
- [x] 6.21. ANNOUNCE
- [ ] 6.22. UNANNOUNCE
- [ ] 6.23. TRACK_STATUS
- [x] 6.24. SUBSCRIBE_ANNOUNCES_OK
- [x] 6.25. SUBSCRIBE_ANNOUNCES_ERROR
