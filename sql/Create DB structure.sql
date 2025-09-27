CREATE TABLE PolicyHolders (
    PolicyHolderId INT IDENTITY(1,1) PRIMARY KEY,
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255) NOT NULL UNIQUE,
    CreatedAt DATETIME2 DEFAULT SYSDATETIME()
);

CREATE TABLE Claims (
    ClaimId INT IDENTITY(1,1) PRIMARY KEY,
    PolicyHolderId INT NOT NULL,
    ClaimNumber NVARCHAR(50) NOT NULL UNIQUE,
    Status NVARCHAR(50) DEFAULT 'New', -- e.g. New, InReview, Closed
    Description NVARCHAR(MAX) NULL,
    CreatedAt DATETIME2 DEFAULT SYSDATETIME(),
    FOREIGN KEY (PolicyHolderId) REFERENCES PolicyHolders(PolicyHolderId)
);


CREATE TABLE ClaimFiles (
    FileId INT IDENTITY(1,1) PRIMARY KEY,
    ClaimId INT NOT NULL,
    FileName NVARCHAR(255) NOT NULL,
    FileType NVARCHAR(50), -- e.g. jpg, pdf, docx
    BlobUrl NVARCHAR(500) NOT NULL, -- link to Blob storage
    ExtractedText NVARCHAR(MAX) NULL, -- OCR or AI processed text
    CreatedAt DATETIME2 DEFAULT SYSDATETIME(),
    FOREIGN KEY (ClaimId) REFERENCES Claims(ClaimId)
);


CREATE TABLE ClaimEmails (
    EmailId INT IDENTITY(1,1) PRIMARY KEY,
    ClaimId INT NOT NULL,
    Sender NVARCHAR(255) NOT NULL,
    Subject NVARCHAR(500),
    Body NVARCHAR(MAX),
    ReceivedAt DATETIME2,
    MessageId NVARCHAR(255) UNIQUE,
    CreatedAt DATETIME2 DEFAULT SYSDATETIME(),
    FOREIGN KEY (ClaimId) REFERENCES Claims(ClaimId)
);



CREATE TABLE AISummaries (
    SummaryId INT IDENTITY(1,1) PRIMARY KEY,
    ClaimId INT NOT NULL,
    SummaryText NVARCHAR(MAX) NOT NULL, -- AI Summary of the claim
    KeyData NVARCHAR(MAX) NULL,         -- JSON with extracted key data (e.g., { "InvoiceAmount": 1200, "InvoiceDate": "2025-09-01" })
    ModelVersion NVARCHAR(50) NULL,     -- Model version used for processing (e.g., gpt-4o-mini)
    CreatedAt DATETIME2 DEFAULT SYSDATETIME(),
    FOREIGN KEY (ClaimId) REFERENCES Claims(ClaimId)
);


INSERT INTO PolicyHolders (FirstName, LastName, Email)
VALUES ('Sergey', 'Pechenkin', 'sergeype@microsoft.com');

SELECT 
    c.ClaimId,
    c.ClaimNumber,
    c.Status,
    ph.FirstName,
    ph.LastName,
    ph.Email,
    e.Subject AS EmailSubject,
    e.Body AS EmailBody,
    f.FileName,
    f.BlobUrl,
    f.ExtractedText,
    s.SummaryText,
    s.KeyData
FROM Claims c
JOIN PolicyHolders ph ON c.PolicyHolderId = ph.PolicyHolderId
LEFT JOIN ClaimEmails e ON c.ClaimId = e.ClaimId
LEFT JOIN ClaimFiles f ON c.ClaimId = f.ClaimId
LEFT JOIN AISummaries s ON c.ClaimId = s.ClaimId
WHERE c.ClaimId = 1;