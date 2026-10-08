public with sharing class ProfileCardController {

    @AuraEnabled
    public static void updateUserPhoto(
        String base64Image,
        String fileName,
        String contentType
    ) {
        if (String.isBlank(base64Image)) {
            throw new AuraHandledException(
                'No image was provided.'
            );
        }

        if (String.isBlank(contentType) ||
            !(contentType == 'image/jpeg' ||
              contentType == 'image/jpg' ||
              contentType == 'image/gif' ||
              contentType == 'image/png')) {

            throw new AuraHandledException(
                'Only JPG, GIF, and PNG images are supported.'
            );
        }

        Blob imageBlob;

        try {
            imageBlob = EncodingUtil.base64Decode(base64Image);
        } catch (Exception e) {
            throw new AuraHandledException(
                'The selected image could not be processed.'
            );
        }

        if (imageBlob.size() > 16 * 1024 * 1024) {
            throw new AuraHandledException(
                'The image must be smaller than 16 MB.'
            );
        }

        ConnectApi.UserProfiles.setPhoto(
            null,
            UserInfo.getUserId(),
            new ConnectApi.BinaryInput(
                imageBlob,
                contentType,
                String.isBlank(fileName)
                    ? 'profile-photo'
                    : fileName
            )
        );
    }
}