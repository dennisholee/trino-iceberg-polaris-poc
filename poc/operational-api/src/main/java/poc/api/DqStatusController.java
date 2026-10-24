package poc.api;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DqStatusController {

    private final GxApiDqGate gate;

    public DqStatusController(GxApiDqGate gate) {
        this.gate = gate;
    }

    @GetMapping("/internal/dq/status")
    public DqDecision status() {
        return gate.last();
    }
}
