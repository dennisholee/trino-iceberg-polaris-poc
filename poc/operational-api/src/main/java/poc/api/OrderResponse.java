package poc.api;

import java.util.List;

public record OrderResponse(
        String correlationId,
        List<OrderView> orders) {
}
