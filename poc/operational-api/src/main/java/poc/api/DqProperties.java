package poc.api;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "dq")
public record DqProperties(
        String geUrl,
        String assetId,
        String contractVersion,
        String endpointClass) {
}
