package poc.api;

import java.math.BigDecimal;
import java.time.Instant;

public record OrderView(
        String orderId,
        String status,
        BigDecimal total,
        Instant lastEventAt) {
}
