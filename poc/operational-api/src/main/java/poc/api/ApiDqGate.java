package poc.api;

public interface ApiDqGate {
    DqDecision evaluate(ApiDqRequest request);
}
