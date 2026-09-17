// Mirrors pkg/doip/doip.go's constants exactly — same values, Dart
// naming convention (lowerCamelCase) instead of Go's exported
// UpperCamelCase.

const int protocolVersion2012 = 0x02;
const int defaultTcpPort = 13400;

const int payloadGenericNegativeAck = 0x0000;
const int payloadRoutingActivationRequest = 0x0005;
const int payloadRoutingActivationResponse = 0x0006;
const int payloadAliveCheckRequest = 0x0007;
const int payloadAliveCheckResponse = 0x0008;
const int payloadDiagnosticMessage = 0x8001;
const int payloadDiagnosticMessagePositiveAck = 0x8002;
const int payloadDiagnosticMessageNegativeAck = 0x8003;

/// The ISO 13400 specification's own default activation type, used
/// because no BMW-specific source confirms what value BMW's ENET
/// adapters actually expect — the best-evidenced fallback, not a
/// confirmed fact. See docs/mhd-live-monitor-v0-plan.md.
const int activationDefault = 0x00;
const int activationDiagnosticRequiredByRegulation = 0x01;
const int activationCentralSecurity = 0xE1;

const int routingDeniedUnknownSourceAddress = 0x00;
const int routingDeniedAllSocketsRegisteredActive = 0x01;
const int routingDeniedSourceAddressMismatch = 0x02;
const int routingDeniedSourceAddressRegistered = 0x03;
const int routingDeniedMissingAuthentication = 0x04;
const int routingDeniedRejectedConfirmation = 0x05;
const int routingDeniedUnsupportedActivationType = 0x06;
const int routingDeniedRequiresTls = 0x07;
const int routingSuccess = 0x10;
const int routingSuccessConfirmationRequired = 0x11;

/// Mirrors pkg/doip.RoutingActivationResponseCode.String().
String describeRoutingCode(int code) {
  switch (code) {
    case routingDeniedUnknownSourceAddress:
      return 'denied: unknown source address';
    case routingDeniedAllSocketsRegisteredActive:
      return 'denied: all sockets registered are active';
    case routingDeniedSourceAddressMismatch:
      return 'denied: source address does not match';
    case routingDeniedSourceAddressRegistered:
      return 'denied: source address already registered';
    case routingDeniedMissingAuthentication:
      return 'denied: missing authentication';
    case routingDeniedRejectedConfirmation:
      return 'denied: rejected confirmation';
    case routingDeniedUnsupportedActivationType:
      return 'denied: unsupported activation type';
    case routingDeniedRequiresTls:
      return 'denied: requires TLS';
    case routingSuccess:
      return 'success';
    case routingSuccessConfirmationRequired:
      return 'success (confirmation required)';
    default:
      return 'unknown response code 0x${code.toRadixString(16).padLeft(2, '0')}';
  }
}
