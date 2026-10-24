package poc.api;

import java.time.Instant;
import java.util.List;

public record DqDecision(
        DqStatus status,
        String runId,
        List<String> failedChecks,
        Instant evaluatedAt) {

    public static DqDecision unknown() {
        return new DqDecision(
                DqStatus.UNKNOWN,
                null,
                List.of("dq service unavailable"),
                Instant.now());
    }
}
