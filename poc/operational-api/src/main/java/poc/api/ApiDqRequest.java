package poc.api;

public record ApiDqRequest(
        String assetId,
        String contractVersion,
        Object payload) {
}
