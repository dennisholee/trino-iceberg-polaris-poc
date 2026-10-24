package poc.api;

import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

@Service
public class GxApiDqGate implements ApiDqGate {

    private final RestClient restClient;
    private final AtomicReference<DqDecision> last = new AtomicReference<>();

    public GxApiDqGate(RestClient.Builder builder, DqProperties properties) {
        this.restClient = builder.baseUrl(properties.geUrl()).build();
    }

    @Override
    public DqDecision evaluate(ApiDqRequest request) {
        try {
            JsonNode response = restClient.post()
                    .uri("/v1/validate")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of(
                            "asset_id", request.assetId(),
                            "contract_version", request.contractVersion(),
                            "payload", request.payload()))
                    .retrieve()
                    .body(JsonNode.class);

            if (response == null) {
                return remember(DqDecision.unknown());
            }

            boolean success = response.path("success").asBoolean(false);
            String runId = response.path("run_id").asText(null);
            List<String> failures = new ArrayList<>();
            response.path("results").forEach(result -> {
                if (!result.path("success").asBoolean(true)) {
                    failures.add(result.path("expectation_config")
                            .path("expectation_type")
                            .asText("check"));
                }
            });

            return remember(new DqDecision(
                    success ? DqStatus.PASS : DqStatus.FAIL,
                    runId,
                    failures,
                    Instant.now()));
        } catch (Exception e) {
            return remember(DqDecision.unknown());
        }
    }

    public DqDecision last() {
        DqDecision decision = last.get();
        return decision == null ? DqDecision.unknown() : decision;
    }

    private DqDecision remember(DqDecision decision) {
        last.set(decision);
        return decision;
    }
}
