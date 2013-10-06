DROP TABLE IF EXISTS `public_memos`;
CREATE TABLE `public_memos` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `memo_id` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO public_memos(memo_id) SELECT id FROM memos WHERE is_private=0;

DELIMITER //

CREATE TRIGGER insert_public_memos AFTER INSERT ON memos
FOR EACH ROW
BEGIN
    IF NEW.is_private = 0 THEN
        INSERT INTO public_memos(memo_id) VALUES (NEW.id);
    END IF
END;//
 
DELIMITER ;