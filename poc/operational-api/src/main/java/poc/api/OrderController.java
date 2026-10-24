package poc.api;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/orders")
public class OrderController {

    private final OrderService orders;
    private final ApiDqGate gate;
    private final DqProperties properties;

    public OrderController(OrderService orders, ApiDqGate gate, DqProperties properties) {
        this.orders = orders;
        this.gate = gate;
        this.properties = properties;
    }

    @GetMapping("/{correlationId}")
    public ResponseEntity<?> get(
            @PathVariable String correlationId,
            @RequestParam(name = "scenario", required = false) String scenario) {

        List<OrderView> rows = orders.findByCorrelation(correlationId);

        // Test-only hook: force a failing response for the gate scenario.
        if ("bad".equalsIgnoreCase(scenario)) {
            rows = List.of(new OrderView(
                    "order-bad",
                    "INVALID",
                    new BigDecimal("-1"),
                    Instant.now()));
        }

        DqDecision decision = gate.evaluate(new ApiDqRequest(
                properties.assetId(),
                properties.contractVersion(),
                rows));

        HttpHeaders headers = new HttpHeaders();
        headers.set("X-DQ-Status", decision.status().name().toLowerCase());
        headers.set("X-Contract-Version", properties.contractVersion());
        if (decision.runId() != null) {
            headers.set("X-DQ-Run-Id", decision.runId());
        }

        if (decision.status() == DqStatus.FAIL || decision.status() == DqStatus.UNKNOWN) {
            return ResponseEntity.status(503)
                    .headers(headers)
                    .body(Map.of(
                            "error", "data quality gate failed",
                            "failures", decision.failedChecks()));
        }

        return ResponseEntity.ok()
                .headers(headers)
                .body(new OrderResponse(correlationId, rows));
    }
}
