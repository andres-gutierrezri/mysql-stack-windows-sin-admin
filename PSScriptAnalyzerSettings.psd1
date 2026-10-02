# Configuración de PSScriptAnalyzer: Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                      # salida interactiva con colores: es un instalador de consola
        'PSUseShouldProcessForStateChangingFunctions',# el modo seguro se ofrece con -DryRun
        'PSUseSingularNouns',                         # nombres de funciones internos descriptivos
        'PSAvoidUsingEmptyCatchBlock',                # limpieza "best effort" (borrado de temporales, difusión de entorno)
        'PSAvoidUsingBrokenHashAlgorithms',           # Oracle publica sumas MD5; solo detectan corrupción (ver docs/LIMITACIONES.md)
        'PSAvoidUsingPlainTextForPassword',           # CurrentPassword se escribe en un .cnf temporal que se sobrescribe y borra
        'PSReviewUnusedParameter'                     # falso positivo: los parámetros se usan desde funciones (ámbito de script)
    )
}
