import Testing

@Suite struct CIAnnotationSmokeTests {
    @Test func intentionalFailureForAnnotationValidation() {
        Issue.record("Intentional failure to verify GitHub Actions annotations (temporary).")
    }
}
