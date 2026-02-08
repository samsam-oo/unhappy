import { resolve, sep } from 'path';

export interface PathValidationResult {
    valid: boolean;
    error?: string;
}

/**
 * Validates that a path is within the allowed working directory
 * @param targetPath - The path to validate (can be relative or absolute)
 * @param workingDirectory - The session's working directory (must be absolute)
 * @returns Validation result
 */
export function validatePath(targetPath: string, workingDirectory: string): PathValidationResult {
    // Resolve both paths to absolute paths to handle path traversal attempts
    const resolvedTarget = resolve(workingDirectory, targetPath);
    const resolvedWorkingDir = resolve(workingDirectory);

    // Check if the resolved target path is within the working directory.
    // Note: `resolvedWorkingDir + '/'` breaks for root paths (e.g. "/" -> "//"), so build a safe prefix.
    const prefix = resolvedWorkingDir.endsWith(sep) ? resolvedWorkingDir : resolvedWorkingDir + sep;
    if (!resolvedTarget.startsWith(prefix) && resolvedTarget !== resolvedWorkingDir) {
        return {
            valid: false,
            error: `Access denied: Path '${targetPath}' is outside the working directory`
        };
    }

    return { valid: true };
}
