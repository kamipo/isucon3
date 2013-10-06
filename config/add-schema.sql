DROP TABLE IF EXISTS `public_memos`;
CREATE TABLE `public_memos` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `memo_id` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO public_memos(memo_id) SELECT id FROM memos WHERE is_private=0 ORDER BY id;

DROP TABLE IF EXISTS `public_memos_count`;
CREATE TABLE `public_memos_count` (
    `max_id` int(11) NOT NULL,
    `count` int(11) NOT NULL
) ENGINE=MEMORY;

INSERT INTO public_memos_count(max_id, count) SELECT MAX(id), COUNT(*) FROM public_memos;

DELIMITER //

DROP TRIGGER IF EXISTS insert_public_memos//
CREATE TRIGGER insert_public_memos AFTER INSERT ON memos
FOR EACH ROW
BEGIN
    IF NEW.is_private = 0 THEN
        INSERT INTO public_memos(memo_id) VALUES (NEW.id);
    END IF;
END;//

DROP TRIGGER IF EXISTS public_memos//
CREATE TRIGGER update_public_memos_count AFTER INSERT ON public_memos
FOR EACH ROW
BEGIN
    UPDATE `public_memos_count` SET max_id = NEW.id, count = count+1;
END;//

 
DELIMITER ;