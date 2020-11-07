/* START OF DATABASE CREATION */

\c postgres

DROP DATABASE IF EXISTS PetCaringService;
CREATE DATABASE PetCaringService;

\c petcaringservice

/*----------------------------------------------------*/

CREATE TABLE Administrator (
	username VARCHAR(20),
	name VARCHAR(100) NOT NULL,
	email VARCHAR(100) NOT NULL UNIQUE,
	password VARCHAR(20) NOT NULL,
	joindate DATE NOT NULL,
	isactive BOOLEAN NOT NULL,
	PRIMARY KEY(username)
);

CREATE TABLE PetOwner (
	username VARCHAR(20),
	name VARCHAR(100) NOT NULL,
	email VARCHAR(100) NOT NULL UNIQUE,
	password VARCHAR(20) NOT NULL,
	joindate DATE NOT NULL,
	isactive BOOLEAN NOT NULL,
	gender VARCHAR(1) NOT NULL,
	address VARCHAR(100) NOT NULL,
	dateofbirth DATE NOT NULL,
	PRIMARY KEY(username)
);

/*----------------------------------------------------*/

CREATE TABLE CareTaker (
	username VARCHAR(20),
	avgrating NUMERIC(2,1) NOT NULL,
	PRIMARY KEY(username),
	FOREIGN KEY(username) REFERENCES PetOwner(username) 
);

CREATE TABLE CareTakerEarnsSalary (
	username VARCHAR(20),
	salarydate DATE NOT NULL,
	totalamount NUMERIC(31, 2) NOT NULL,
	PRIMARY KEY(username, salarydate),
	FOREIGN KEY(username) REFERENCES CareTaker(username) ON DELETE CASCADE
);

/*----------------------------------------------------*/

CREATE TABLE FullTime (
	username VARCHAR(20),
	PRIMARY KEY(username),
	FOREIGN KEY(username) REFERENCES CareTaker(username)		
);

CREATE TABLE FullTimeAppliesLeaves (
	username VARCHAR(20),
	leavedate DATE,
	PRIMARY KEY(username, leavedate),
	FOREIGN KEY(username) REFERENCES FullTime(username)	ON DELETE CASCADE	
);

CREATE TABLE PartTime (
	username VARCHAR(20),
	PRIMARY KEY(username),
	FOREIGN KEY(username) REFERENCES CareTaker(username)		
);

CREATE TABLE PartTimeIndicatesAvailability (
	username VARCHAR(20),
	startdate DATE NOT NULL,
	enddate DATE NOT NULL,
	PRIMARY KEY(username, startDate, endDate),
	FOREIGN KEY(username) REFERENCES PartTime(username) ON DELETE CASCADE
);

/*----------------------------------------------------*/

CREATE TABLE PetOwnerRegistersCreditCard (
	username VARCHAR(20),
	cardnumber VARCHAR(20) UNIQUE,
	nameoncard VARCHAR(100) NOT NULL,
	cvv VARCHAR(20) NOT NULL,
	expirydate DATE NOT NULL,
	PRIMARY KEY(username, cardnumber),
	FOREIGN KEY(username) REFERENCES PetOwner(username)	ON DELETE CASCADE
);

/*----------------------------------------------------*/

CREATE TABLE PetCategory (
	category VARCHAR(20),
	baseprice NUMERIC(31,2) NOT NULL,
	PRIMARY KEY(category)
);

CREATE TABLE CareTakerCatersPetCategory (
	username VARCHAR(20) NOT NULL,
	category VARCHAR(20) NOT NULL,
	price NUMERIC(31,2) NOT NULL,
	PRIMARY KEY(username, category),
	FOREIGN KEY(username) REFERENCES CareTaker(username),
	FOREIGN KEY(category) REFERENCES PetCategory(category)	
);

CREATE TABLE Pet (
	username VARCHAR(20),
	name VARCHAR(50),
	dateofbirth DATE NOT NULL,
	gender VARCHAR(1) NOT NULL,
	description VARCHAR(100) NOT NULL,
	specialreqs VARCHAR(100),
	personality VARCHAR(100) NOT NULL,
	category VARCHAR(20) NOT NULL,
	PRIMARY KEY(username, name),
	FOREIGN KEY(username) REFERENCES PetOwner(username),	
	FOREIGN KEY(category) REFERENCES PetCategory(category)	
);

/*----------------------------------------------------*/

CREATE TABLE Job (
	ctusername VARCHAR(20),
	pousername VARCHAR(20),	
	petname VARCHAR(20),
	startdate DATE,
	enddate DATE NOT NULL,
	requestdate TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
	status VARCHAR(10) DEFAULT 'CONFIRMED' NOT NULL,
	rating NUMERIC(2,1),
	paymenttype VARCHAR(20) NOT NULL,
	deliverytype VARCHAR(20) NOT NULL,
	amountpaid NUMERIC(31,2) NOT NULL,
	review VARCHAR(1000),
	PRIMARY KEY(pousername, ctusername, petname, startdate),
	FOREIGN KEY(pousername, petname) REFERENCES Pet(username, name),
	FOREIGN KEY(ctusername) REFERENCES CareTaker(username),
	CHECK(pousername != ctusername),
	CHECK(startdate < enddate),
	CHECK(requestdate < enddate)
);

/* END OF DATABASE CREATION */

/* START OF TRIGGERS */
/* Update CareTaker.avgrating through Job */
/*----------------------------------------------------*/

CREATE OR REPLACE FUNCTION update_avg_rating()
  RETURNS TRIGGER AS
$$
DECLARE 
    newavgrating NUMERIC(2,1);
BEGIN
  newavgrating = (SELECT AVG(NULLIF(rating,0)) FROM job WHERE ctusername = OLD.ctusername);

  IF newavgrating IS NULL THEN
	UPDATE caretaker
    SET avgrating = 0
	WHERE username = OLD.ctusername;
    RETURN NEW;
    ELSE
	UPDATE caretaker
	SET avgrating = newavgrating
	WHERE username = OLD.ctusername;
    RETURN NEW;
  END IF;
END
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER update_avg_rating
AFTER UPDATE
ON job
FOR EACH ROW
EXECUTE PROCEDURE update_avg_rating();

/* Create default Cater entry when new CareTaker created */
/*----------------------------------------------------*/

CREATE OR REPLACE FUNCTION create_petcat()
  RETURNS TRIGGER AS
$$
BEGIN
  INSERT INTO CareTakerCatersPetCategory(username, category, price)
  VALUES(NEW.username, 'Dogs', (SELECT baseprice FROM petcategory where category = 'Dogs'));
  RETURN NEW;
END
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER create_petcat
AFTER INSERT
ON caretaker
FOR EACH ROW
EXECUTE PROCEDURE create_petcat();

/* Caculate Job total price based on days and base price */
/*----------------------------------------------------*/

CREATE OR REPLACE FUNCTION calc_job_price()
  RETURNS TRIGGER AS
$$
BEGIN
  IF new.status = 'PENDING' THEN 
  new.amountpaid := 0.0;
  ELSEIF new.status = 'CANCELLED' THEN
  new.amountpaid := 0.0;
  ELSE 
  new.amountpaid := (date_part('day', new.enddate::timestamp - new.startdate::timestamp) 
  					* (SELECT price FROM caretakercaterspetcategory WHERE username = new.ctusername AND category 
					= (SELECT category FROM pet WHERE username = new.pousername AND name = new.petname)));
  END IF;
  RETURN NEW;  
END
$$
LANGUAGE plpgsql;

CREATE TRIGGER calc_job_price
BEFORE INSERT
ON job
FOR EACH ROW
EXECUTE PROCEDURE calc_job_price();

/* Caculate base price with reference to rating when insert new pets caretaker can take */
/*----------------------------------------------------*/

CREATE OR REPLACE FUNCTION set_baseprice()
  RETURNS TRIGGER AS
$$
DECLARE 
    newavgrating NUMERIC(2,1);
    currbaseprice NUMERIC(31,2);
BEGIN
    newavgrating = (SELECT avgrating FROM caretaker WHERE username = new.username);
    currbaseprice = (SELECT baseprice FROM petcategory WHERE category = new.category);

    IF newavgrating = 5.0 THEN
    new.price := currbaseprice * 2;
    RETURN NEW;
    ELSEIF newavgrating < 5.0 AND newavgrating >= 4.5 THEN
    new.price := currbaseprice * 1.75;
    RETURN NEW;
    ELSEIF newavgrating < 4.5 AND newavgrating >= 4.0 THEN
    new.price := currbaseprice * 1.5;
    RETURN NEW;
    ELSEIF newavgrating < 4.0 AND newavgrating >= 3.5 THEN
    new.price := currbaseprice * 1.25;
    RETURN NEW;
    ELSE
    new.price := currbaseprice;
    RETURN NEW;
  END IF;
END
$$
LANGUAGE plpgsql;

CREATE TRIGGER set_baseprice
BEFORE INSERT
ON CareTakerCatersPetCategory
FOR EACH ROW
EXECUTE PROCEDURE set_baseprice();

/* Caculate base price with reference to rating on update */
/*----------------------------------------------------*/

CREATE OR REPLACE FUNCTION update_baseprice()
  RETURNS TRIGGER AS
$$
DECLARE
    currbaseprice NUMERIC(31,2);
  newprice NUMERIC(31,2);
  cater CareTakerCatersPetCategory%rowtype;
BEGIN

  FOR cater IN SELECT * FROM CareTakerCatersPetCategory WHERE username = new.username LOOP
    currbaseprice = (SELECT baseprice FROM petcategory WHERE category = cater.category);

    IF new.avgrating = 5.0 THEN
      UPDATE CareTakerCatersPetCategory
      SET price = currbaseprice * 2 
      WHERE username = new.username AND category = cater.category;
      RETURN NEW;
    ELSEIF new.avgrating < 5.0 AND new.avgrating >= 4.5 THEN
      UPDATE CareTakerCatersPetCategory
      SET price = currbaseprice * 1.75
      WHERE username = new.username AND category = cater.category;
      RETURN NEW;
    ELSEIF new.avgrating < 4.5 AND new.avgrating >= 4.0 THEN
      UPDATE CareTakerCatersPetCategory
      SET price = currbaseprice * 1.5
      WHERE username = new.username AND category = cater.category;
      RETURN NEW;
    ELSEIF new.avgrating < 4.0 AND new.avgrating >= 3.5 THEN
      UPDATE CareTakerCatersPetCategory
      SET price = currbaseprice * 1.25
      WHERE username = new.username AND category = cater.category;
      RETURN NEW;
    ELSE
      UPDATE CareTakerCatersPetCategory
      SET price = currbaseprice
      WHERE username = new.username AND category = cater.category;
      RETURN NEW;
      
    END IF;
  END LOOP;
END
$$
LANGUAGE plpgsql;

CREATE TRIGGER update_baseprice
AFTER UPDATE
ON caretaker
FOR EACH ROW
EXECUTE PROCEDURE update_baseprice();

/* Limit leaves application if condition not met */
/*----------------------------------------------------*/

CREATE OR REPLACE FUNCTION limit_leaves()
    RETURNS TRIGGER AS
$$
DECLARE
  prevdate fulltimeappliesleaves%rowtype;
    prevprevdate DATE;
    lastdate DATE;
    consecdays integer := 0;
BEGIN

    IF new.leavedate < CURRENT_DATE THEN
      RAISE EXCEPTION 'Please select a future date';
    END IF;

    FOR prevdate IN SELECT * FROM fulltimeappliesleaves 
        WHERE username = new.username 
          AND date_part('year', leavedate) = date_part('year', CURRENT_DATE) 
          ORDER BY leavedate DESC LOOP

    prevprevdate = (SELECT * FROM fulltimeappliesleaves 
      WHERE username = new.username 
        AND leavedate < prevdate.leavedate 
        ORDER BY leavedate DESC
        LIMIT 1);

    IF prevdate != null THEN
      IF prevdate.leavedate - prevprevdate >= 300 THEN
        consecdays := consecdays + 2;
      ELSEIF prevdate.leavedate - prevprevdate >= 150 THEN
        consecdays := consecdays + 1;
      END IF;
    END IF;

    END LOOP;

  lastdate: = (SELECT * FROM fulltimeappliesleaves 
      WHERE username = new.username 
        AND leavedate < CURRENT_DATE 
        AND date_part('year', leavedate) = date_part('year', CURRENT_DATE) 
        ORDER BY leavedate DESC LIMIT 1);
        
  IF CURRENT_DATE - lastdate >= 300 THEN
    consecdays := consecdays + 2;
  ELSEIF CURRENT_DATE - lastdate >= 150 THEN
    consecdays := consecdays + 1;
  END IF;

  IF consecdays < 2 THEN
    RAISE EXCEPTION 'Invalid date, you need to work for at least 2x150 consecutive days a year.';
  END IF;
  
  RETURN NEW;
END
$$
LANGUAGE plpgsql;

CREATE TRIGGER limit_leaves
BEFORE INSERT
ON fulltimeappliesleaves
FOR EACH ROW
EXECUTE PROCEDURE limit_leaves();

/*----------------------------------------------------*/

/* END OF TRIGGERS */

/* START OF DATA INITIALISATION */
/* Administrator 10*/
INSERT INTO Administrator VALUES ('admin', 'admin', 'admin@pcs.com', 'admin', '2020-08-24', 'true');
INSERT INTO Administrator VALUES ('Iorgo', 'Matty', 'mhanton0@cnet.com', 'cxQTSfK6TLa', '2009-01-04', 'true');
INSERT INTO Administrator VALUES ('Carver', 'Farlay', 'fharold1@soup.io', 'FcNsgj', '2005-03-10', 'false');
INSERT INTO Administrator VALUES ('Annalee', 'Yelena', 'ylesly2@cam.ac.uk', 'XfzLZqRQWEPv', '2004-01-07', 'true');
INSERT INTO Administrator VALUES ('Mayne', 'Lorri', 'lstockford3@exblog.jp', 'uTOwhPo0', '2010-02-10', 'true');
INSERT INTO Administrator VALUES ('Daffy', 'Sib', 'showis4@google.com', 'c9XBAOzZu', '2017-02-15', 'true');
INSERT INTO Administrator VALUES ('Kelsi', 'Kelwin', 'kvye5@woothemes.com', 'ArFjIvb5C', '2019-02-01', 'true');
INSERT INTO Administrator VALUES ('Lucie', 'Danie', 'dbrough6@gravatar.com', 'qp1qgK8FgH9', '2020-01-14', 'true');
INSERT INTO Administrator VALUES ('Joice', 'Alecia', 'ablacket7@theatlantic.com', 'EoqICLbqOig', '2001-07-10', 'false');
INSERT INTO Administrator VALUES ('Laughton', 'Nanine', 'nnewbery8@hao123.com', 's1AIBuf1NJ', '2005-04-26', 'false');

/*----------------------------------------------------*/
/* App User 1000 */
INSERT INTO PetOwner VALUES ('Clemens', 'Angelico', 'acorp0@msn.com', 'kUhUxSZd', '2019-05-06', 'true', 'M', '6 Lighthouse Bay Trail', '2015-12-19');
INSERT INTO PetOwner VALUES ('Georgetta', 'Dionis', 'dthreader1@aol.com', 't6dI8Um7yq', '2016-07-15', 'false', 'F', '03 American Ash Alley', '1996-04-02');
INSERT INTO PetOwner VALUES ('Tabor', 'Erhard', 'eblackmuir2@europa.eu', 'FvPwOd0jq', '2001-11-17', 'true', 'M', '64085 Carey Terrace', '1968-06-04');
INSERT INTO PetOwner VALUES ('Fern', 'Giana', 'gspinley3@ucsd.edu', 'kxcMAkHj6', '2010-08-17', 'false', 'F', '7306 Schiller Center', '1975-10-22');
INSERT INTO PetOwner VALUES ('Abby', 'Lorin', 'lkassidy4@geocities.jp', 'B9cRmZ', '2012-09-19', 'false', 'M', '5 Stephen Pass', '1932-12-25');
INSERT INTO PetOwner VALUES ('Aron', 'Freeman', 'falexsandrovich5@mayoclinic.com', 'VVF5gbcMH8O', '2017-07-16', 'true', 'M', '08899 Sachs Court', '1998-06-08');
INSERT INTO PetOwner VALUES ('Clementius', 'Ellerey', 'ewickham6@soup.io', 'ogfX2TuUa', '2010-12-08', 'true', 'M', '07827 Lakewood Gardens Alley', '2018-10-29');
INSERT INTO PetOwner VALUES ('Gare', 'Christoffer', 'ckarpets7@digg.com', 'qqwUNC7a95av', '2013-03-26', 'false', 'M', '84434 Monica Center', '1956-12-02');
INSERT INTO PetOwner VALUES ('Cybil', 'Estrella', 'ebottjer8@flavors.me', 'IXqwVnl', '2013-02-15', 'true', 'F', '957 Butterfield Junction', '1962-09-29');
INSERT INTO PetOwner VALUES ('Brendon', 'Brad', 'bhatton9@foxnews.com', 'eUyAO3BxUS', '2011-04-09', 'true', 'M', '47 Northfield Center', '1959-10-25');
INSERT INTO PetOwner VALUES ('Petr', 'Borden', 'baslina@usda.gov', '6bqjMpKf', '2013-05-14', 'true', 'M', '13116 Florence Terrace', '1992-05-21');
INSERT INTO PetOwner VALUES ('Frederica', 'Lindsy', 'lfloydb@gravatar.com', 'jZNMo1xmefUK', '2012-03-17', 'false', 'F', '7 Lien Park', '1939-03-05');
INSERT INTO PetOwner VALUES ('Gwenni', 'Bekki', 'bhakeyc@bizjournals.com', 'bIVA5KsWy8dP', '2011-09-18', 'false', 'F', '1749 Northwestern Plaza', '2000-12-11');
INSERT INTO PetOwner VALUES ('Wood', 'Fonsie', 'fdewend@about.me', 'RrwWaSE6fiLG', '2020-02-12', 'true', 'M', '3736 Michigan Pass', '1982-09-29');
INSERT INTO PetOwner VALUES ('Von', 'Niel', 'ncheyennee@omniture.com', 'C0bKTv', '2019-11-04', 'false', 'M', '10 Bonner Court', '1957-06-01');
INSERT INTO PetOwner VALUES ('Eba', 'Margret', 'mthorbonf@blogger.com', 'JrkQR6', '2018-07-17', 'true', 'F', '78 Butternut Way', '1932-05-03');
INSERT INTO PetOwner VALUES ('Avram', 'Sigismund', 'schalderg@admin.ch', 'afQ6HW', '2014-02-03', 'true', 'M', '1762 6th Junction', '1937-06-02');
INSERT INTO PetOwner VALUES ('Nilson', 'Isador', 'iprocterh@yellowpages.com', '0MfXXpr28h', '2014-06-21', 'true', 'M', '3 Delladonna Point', '1941-04-01');
INSERT INTO PetOwner VALUES ('Gran', 'Micky', 'macremani@digg.com', 'hh9adBdDs2', '2006-10-28', 'true', 'M', '949 Orin Lane', '1930-12-03');
INSERT INTO PetOwner VALUES ('Janos', 'Ansel', 'alevershaj@pen.io', 'zFMo31hqManO', '2019-01-21', 'false', 'M', '24320 Londonderry Street', '1946-10-28');
INSERT INTO PetOwner VALUES ('Dion', 'Hildagard', 'hkilshawk@examiner.com', 'IHyGDJKmJM', '2016-08-08', 'true', 'F', '2 Melvin Junction', '1977-01-15');
INSERT INTO PetOwner VALUES ('Dalton', 'Tades', 'tgeistmannl@reverbnation.com', 'QzWWZU1GRqD', '2005-08-10', 'true', 'M', '8112 School Drive', '2017-02-09');
INSERT INTO PetOwner VALUES ('Eilis', 'Georgianne', 'gtwiggem@guardian.co.uk', 'pDKyj46vSb', '2020-03-25', 'true', 'F', '31699 Manitowish Drive', '1994-11-04');
INSERT INTO PetOwner VALUES ('Earle', 'Holly', 'hfilyashinn@acquirethisname.com', '9BnFTS8GYzh', '2019-01-05', 'false', 'M', '29 Northland Point', '1950-09-19');
INSERT INTO PetOwner VALUES ('Irma', 'Erda', 'edebeauchempo@istockphoto.com', 'SjaoYArbarAB', '2003-11-19', 'true', 'F', '1 Dixon Junction', '1951-10-06');
INSERT INTO PetOwner VALUES ('Joseito', 'Mord', 'mbartulp@wisc.edu', '0UAcmN5', '2008-01-03', 'false', 'M', '61 Iowa Park', '1976-03-16');
INSERT INTO PetOwner VALUES ('Frannie', 'Belita', 'bdrinkallq@huffingtonpost.com', '9HWQVk', '2012-07-17', 'true', 'F', '07808 Doe Crossing Crossing', '1949-08-31');
INSERT INTO PetOwner VALUES ('Steven', 'Salvidor', 'scosslettr@slideshare.net', 'vaA42PWG', '2012-11-05', 'true', 'M', '3 Dwight Place', '1959-04-17');
INSERT INTO PetOwner VALUES ('Donia', 'Jermaine', 'jcardwells@washingtonpost.com', 'cc3P3Rm', '2001-11-18', 'false', 'F', '65859 Roxbury Drive', '1997-02-19');
INSERT INTO PetOwner VALUES ('Grant', 'Cyrillus', 'cheggt@independent.co.uk', 'X0y6Afl', '2020-02-11', 'false', 'M', '584 Namekagon Avenue', '1976-06-22');
INSERT INTO PetOwner VALUES ('Pepe', 'Keelby', 'kkintonu@netlog.com', 'Izwix3sZ', '2001-08-30', 'false', 'M', '8300 Armistice Park', '1991-03-15');
INSERT INTO PetOwner VALUES ('Elsa', 'Rosalind', 'rgerlingv@ezinearticles.com', 'z4bRM6Bx', '2001-06-28', 'false', 'F', '22342 Lyons Junction', '2017-06-13');
INSERT INTO PetOwner VALUES ('Shelagh', 'Pepita', 'pcreevyw@technorati.com', 'r6IOE7S0P5O3', '2006-11-15', 'false', 'F', '42 Brickson Park Drive', '1951-08-11');
INSERT INTO PetOwner VALUES ('Mahmoud', 'Donall', 'dmumx@ca.gov', '1MaCfv', '2007-12-02', 'false', 'M', '39137 Valley Edge Drive', '1960-07-28');
INSERT INTO PetOwner VALUES ('Bastian', 'Winny', 'wkerfuty@etsy.com', 'HZlwgU', '2008-11-16', 'true', 'M', '81950 Waubesa Pass', '2010-12-14');
INSERT INTO PetOwner VALUES ('Erin', 'Romola', 'rbevesz@histats.com', 'et2Ml9VvD', '2005-02-25', 'false', 'F', '2361 Sommers Alley', '1933-07-04');
INSERT INTO PetOwner VALUES ('Cordelia', 'Margret', 'msmoote10@sina.com.cn', 'ZuSn6hTFcMUY', '2003-05-25', 'true', 'F', '21 Delladonna Avenue', '1966-07-15');
INSERT INTO PetOwner VALUES ('Herbert', 'Vince', 'vplayden11@wikispaces.com', 'aukLBEwqo62', '2014-05-22', 'true', 'M', '3 Prairieview Circle', '1948-12-24');
INSERT INTO PetOwner VALUES ('Hedy', 'Ameline', 'agoodday12@zdnet.com', '8pg9m7u4z', '2017-01-09', 'true', 'F', '46911 Florence Center', '1950-04-25');
INSERT INTO PetOwner VALUES ('Raven', 'Happy', 'hshowte13@sogou.com', 'kSpgImvkZ09a', '2019-12-11', 'true', 'F', '1 Derek Lane', '1931-06-09');
INSERT INTO PetOwner VALUES ('Berenice', 'Penni', 'pbramwich14@google.nl', 'vrRyf6XH', '2009-12-20', 'true', 'F', '60872 Basil Hill', '1978-11-23');
INSERT INTO PetOwner VALUES ('Giorgia', 'Leanora', 'lkuhle15@vk.com', 'awPel8e', '2015-01-16', 'false', 'F', '3281 Aberg Pass', '1947-07-18');
INSERT INTO PetOwner VALUES ('Courtenay', 'Elonore', 'ejanson16@oracle.com', 'x0AAFT', '2000-11-04', 'true', 'F', '294 Mccormick Court', '2016-04-28');
INSERT INTO PetOwner VALUES ('Lulita', 'Sibyl', 'srosenstein17@drupal.org', '0818MpWG', '2014-01-03', 'true', 'F', '95 Nobel Pass', '2020-08-27');
INSERT INTO PetOwner VALUES ('Nataniel', 'Bordy', 'bdymidowicz18@google.ca', 'zkBUVwFsHag', '2003-07-29', 'false', 'M', '42 Monterey Street', '2009-07-31');
INSERT INTO PetOwner VALUES ('Hayley', 'Zarla', 'zzamora19@w3.org', 'bSO2SorNUNM', '2015-04-16', 'false', 'F', '2872 Luster Terrace', '1980-06-28');
INSERT INTO PetOwner VALUES ('Maisey', 'Thekla', 'thuerta1a@xinhuanet.com', 'KEWDsw2', '2012-05-26', 'false', 'F', '88 Buell Avenue', '1959-02-02');
INSERT INTO PetOwner VALUES ('Ruthanne', 'Farica', 'fmcorkill1b@economist.com', 'ICPoWYAiUfHE', '2011-05-04', 'true', 'F', '551 Stone Corner Lane', '1968-12-02');
INSERT INTO PetOwner VALUES ('Giuditta', 'Allene', 'ashoveller1c@github.com', 'hQvaFs', '2017-09-02', 'true', 'F', '7818 Manufacturers Pass', '1930-11-15');
INSERT INTO PetOwner VALUES ('Garth', 'Winslow', 'wgrancher1d@fastcompany.com', 'zSmTNQgujiQt', '2020-05-15', 'true', 'M', '767 Jenna Park', '1951-08-21');
INSERT INTO PetOwner VALUES ('Dierdre', 'Tamera', 'tgive1e@weather.com', 'lE3Z2q', '2019-09-22', 'false', 'F', '0525 Fisk Hill', '1998-03-21');
INSERT INTO PetOwner VALUES ('Clyde', 'Lyell', 'ldockerty1f@gmpg.org', 'Z9P0JZc3zV', '2006-03-01', 'true', 'M', '08 Dakota Trail', '1959-01-30');
INSERT INTO PetOwner VALUES ('Hymie', 'Uriel', 'ugarbert1g@si.edu', 'QnLz61', '2008-05-02', 'false', 'M', '830 Sundown Place', '2011-06-03');
INSERT INTO PetOwner VALUES ('Timmie', 'Wilow', 'wfenna1h@census.gov', '4fqP7orp', '2009-10-04', 'false', 'F', '85077 Pepper Wood Street', '1950-03-30');
INSERT INTO PetOwner VALUES ('Eulalie', 'Ilyse', 'imcarthur1i@reddit.com', 'pmkdHV', '2006-11-01', 'false', 'F', '484 Annamark Avenue', '2000-11-09');
INSERT INTO PetOwner VALUES ('Spike', 'Sargent', 'sbartaletti1j@elpais.com', 'wpKAVaKJ', '2006-08-03', 'false', 'M', '38734 Debra Crossing', '1964-05-23');
INSERT INTO PetOwner VALUES ('Conant', 'Waverly', 'wheinrici1k@nba.com', 'azMhrA', '2010-11-05', 'false', 'M', '6 3rd Junction', '1986-03-10');
INSERT INTO PetOwner VALUES ('Walker', 'Ado', 'afedorchenko1l@github.com', '8tB5DWy', '2012-05-08', 'false', 'M', '20120 Ohio Plaza', '2002-03-13');
INSERT INTO PetOwner VALUES ('Norby', 'Jodi', 'jsiemons1m@histats.com', 'LRq4JKZQbp', '2016-04-09', 'true', 'M', '9625 Glacier Hill Lane', '2002-01-21');
INSERT INTO PetOwner VALUES ('Debbi', 'Gianna', 'gscowcroft1n@yellowpages.com', 'LkVFSqlNM9Us', '2012-10-09', 'false', 'F', '15656 Knutson Terrace', '1942-06-28');
INSERT INTO PetOwner VALUES ('Uta', 'Alene', 'ajanks1p@china.com.cn', 'rVrz058pm2RH', '2011-07-29', 'false', 'F', '8 Lukken Trail', '2009-01-31');
INSERT INTO PetOwner VALUES ('Briano', 'Quincey', 'qmckinlay1q@netvibes.com', 'gXPxQuA7b', '2015-01-05', 'false', 'M', '080 Old Gate Parkway', '1991-10-27');
INSERT INTO PetOwner VALUES ('Flem', 'Mort', 'mtatham1r@nifty.com', 'm2XDilQ', '2017-09-20', 'true', 'M', '6 Karstens Alley', '2018-11-19');
INSERT INTO PetOwner VALUES ('Dalt', 'Delmer', 'dlerway1s@fema.gov', 'v6rEsf65AP', '2018-08-22', 'true', 'M', '93391 Ridgeview Drive', '1990-11-27');
INSERT INTO PetOwner VALUES ('Lorilyn', 'Trista', 'ttesyro1t@netvibes.com', 'MdbnzQ9sU', '2006-08-29', 'false', 'F', '7779 Northfield Park', '1961-09-17');
INSERT INTO PetOwner VALUES ('Tremaine', 'Akim', 'abiggerdike1u@hostgator.com', 'vKNttS', '2001-11-28', 'false', 'M', '321 Bowman Crossing', '1981-09-12');
INSERT INTO PetOwner VALUES ('Dalston', 'Allin', 'aklazenga1v@ifeng.com', 'oKYRce', '2012-08-20', 'true', 'M', '66 Jay Road', '1976-10-14');
INSERT INTO PetOwner VALUES ('Janina', 'Myrta', 'moaten1w@sohu.com', 'bqKCw2kF6', '2007-06-09', 'false', 'F', '577 Esker Plaza', '1983-06-30');
INSERT INTO PetOwner VALUES ('Baron', 'Cletus', 'cplet1x@columbia.edu', 'ngbXBQj', '2009-10-31', 'false', 'M', '41 Welch Place', '1978-11-12');
INSERT INTO PetOwner VALUES ('Cirilo', 'Adolph', 'agrinval1y@mediafire.com', 'GMwRB5J9BDU4', '2008-07-19', 'true', 'M', '84 Blackbird Hill', '1932-02-28');
INSERT INTO PetOwner VALUES ('Rafaello', 'Ode', 'ozaniolo1z@craigslist.org', 'uiu4Y7LIm', '2005-08-01', 'true', 'M', '5663 Onsgard Court', '1992-11-25');
INSERT INTO PetOwner VALUES ('Rossy', 'Elvin', 'erickis20@godaddy.com', 'ufKiWVySwU', '2016-09-30', 'true', 'M', '646 Grayhawk Road', '1946-04-07');
INSERT INTO PetOwner VALUES ('Allyson', 'Stacia', 'swrankling21@miibeian.gov.cn', 'Qp55ti9dxPp', '2009-10-06', 'true', 'F', '7817 Heath Alley', '2005-03-26');
INSERT INTO PetOwner VALUES ('Burke', 'Raynard', 'rdutton22@privacy.gov.au', 'vzajTUWEGo', '2011-03-30', 'false', 'M', '3950 Butterfield Place', '1988-06-20');
INSERT INTO PetOwner VALUES ('Townie', 'Jamison', 'jspinige23@kickstarter.com', 'QW2SqWku6m', '2007-11-28', 'true', 'M', '4376 Sloan Street', '1949-01-04');
INSERT INTO PetOwner VALUES ('Bax', 'Tremaine', 'tmonkley24@google.de', '5VYBythy', '2019-10-22', 'false', 'M', '58587 Maple Street', '2011-06-29');
INSERT INTO PetOwner VALUES ('Arel', 'Bryan', 'bharbert25@dagondesign.com', 'PCpD1vBkuEhE', '2019-08-12', 'false', 'M', '43 Dahle Way', '1949-05-31');
INSERT INTO PetOwner VALUES ('Antoni', 'Stavro', 'ssegeswoeth26@dell.com', 'MqHfT1n2HG4P', '2004-09-25', 'true', 'M', '367 Nova Street', '1935-10-06');
INSERT INTO PetOwner VALUES ('Clementine', 'Malissa', 'mstidston27@nba.com', 'osPV5k', '2011-09-26', 'true', 'F', '51 Bayside Avenue', '1951-03-07');
INSERT INTO PetOwner VALUES ('Bernardina', 'Evy', 'econrad28@51.la', 'r5T1ydXl', '2016-05-30', 'true', 'F', '713 Maple Parkway', '2020-03-08');
INSERT INTO PetOwner VALUES ('Cass', 'Karine', 'kgrindley29@tinyurl.com', 'pwqYJxZV', '2004-05-13', 'true', 'F', '61818 Delaware Lane', '1998-05-15');
INSERT INTO PetOwner VALUES ('Dacie', 'Deeyn', 'dleads2a@stumbleupon.com', 'sr35gNSfzEJs', '2014-04-02', 'false', 'F', '41280 Holy Cross Circle', '1937-09-17');
INSERT INTO PetOwner VALUES ('Bernetta', 'Marielle', 'madnams2b@wix.com', 'ubxoeER9e', '2007-04-19', 'false', 'F', '4655 Golf View Road', '2015-04-22');
INSERT INTO PetOwner VALUES ('Ursola', 'Orella', 'oscopham2c@youku.com', 'C8HKil1', '2001-08-06', 'true', 'F', '503 Kenwood Center', '1979-10-20');
INSERT INTO PetOwner VALUES ('Melvyn', 'Brant', 'bdovinson2d@symantec.com', 'ldfxQsf8', '2014-01-29', 'true', 'M', '6 Golf Course Junction', '1986-02-13');
INSERT INTO PetOwner VALUES ('Cary', 'Alonso', 'ascrogges2e@ed.gov', '2diDwy', '2009-10-29', 'false', 'M', '2358 Park Meadow Avenue', '2010-05-08');
INSERT INTO PetOwner VALUES ('Ellswerth', 'Weber', 'wkluge2f@artisteer.com', 'o9CjvKg', '2016-03-21', 'true', 'M', '7 Summit Junction', '1965-09-05');
INSERT INTO PetOwner VALUES ('Binnie', 'Katinka', 'kyoules2g@i2i.jp', 'eCvFmCw8rj', '2003-05-14', 'true', 'F', '71520 Fair Oaks Plaza', '1931-10-08');
INSERT INTO PetOwner VALUES ('Danie', 'Gardner', 'glomis2h@ucoz.com', 'z1wOTHl', '2012-07-28', 'false', 'M', '288 Comanche Drive', '1976-02-11');
INSERT INTO PetOwner VALUES ('Malcolm', 'Lyman', 'lcallam2i@wikispaces.com', 'WSNVWrhM', '2014-04-13', 'false', 'M', '07 Gulseth Crossing', '1992-03-18');
INSERT INTO PetOwner VALUES ('Napoleon', 'Rusty', 'rmaier2j@craigslist.org', 'NZG0929Rm', '2012-09-18', 'true', 'M', '1688 Kim Terrace', '1945-01-19');
INSERT INTO PetOwner VALUES ('Phineas', 'Hilarius', 'hshorey2k@webeden.co.uk', 'ppD1pTF', '2015-05-27', 'true', 'M', '91 Bonner Way', '1968-04-15');
INSERT INTO PetOwner VALUES ('Farah', 'Alleen', 'amedlen2l@nationalgeographic.com', 'waRs1Bv', '2019-05-23', 'true', 'F', '13953 Jenna Alley', '2004-02-13');
INSERT INTO PetOwner VALUES ('Loise', 'Valera', 'vpilpovic2m@gmpg.org', 'c3KzO2vf', '2014-09-12', 'false', 'F', '41736 Twin Pines Parkway', '1953-12-03');
INSERT INTO PetOwner VALUES ('Tore', 'Peter', 'pslewcock2n@sbwire.com', 'E1gyDeCbh', '2012-03-20', 'true', 'M', '42 Morrow Junction', '1949-07-17');
INSERT INTO PetOwner VALUES ('Fayre', 'Morissa', 'mmackellen2o@deliciousdays.com', '7pXm4mweso', '2012-08-22', 'true', 'F', '90 Delladonna Alley', '1947-10-21');
INSERT INTO PetOwner VALUES ('Kylie', 'Hodge', 'hsnelling2p@51.la', 'GRZjv5UUJNX', '2018-11-19', 'true', 'M', '456 Cascade Road', '1968-08-07');
INSERT INTO PetOwner VALUES ('Natty', 'Bartel', 'bscholl2q@usgs.gov', 'ThgAg2X', '2003-06-28', 'true', 'M', '7833 Loftsgordon Alley', '1984-07-04');
INSERT INTO PetOwner VALUES ('Cece', 'Skelly', 'spiatkow2r@gmpg.org', 'Aexldp', '2003-07-14', 'false', 'M', '19 Summerview Center', '2006-09-10');
INSERT INTO PetOwner VALUES ('Kali', 'Molli', 'mcarley2s@homestead.com', 'gfHLI8lK6', '2018-04-18', 'true', 'F', '0 Lakewood Alley', '1946-10-09');
INSERT INTO PetOwner VALUES ('Waverley', 'Stillman', 'stheseira2t@walmart.com', 'ZJ5U2HS', '2001-02-06', 'false', 'M', '2 Merrick Lane', '1976-08-05');
INSERT INTO PetOwner VALUES ('Diena', 'Nikkie', 'nbasillon2u@miitbeian.gov.cn', 'RuOKqO', '2003-10-03', 'true', 'F', '3778 Larry Way', '2011-06-02');
INSERT INTO PetOwner VALUES ('Hunter', 'Bobbie', 'bcrutchfield2v@cloudflare.com', 'Y9roUZ6EifT', '2003-12-02', 'true', 'M', '800 Dawn Parkway', '1956-09-01');
INSERT INTO PetOwner VALUES ('Darnell', 'Ezekiel', 'emoxon2w@bbb.org', 'Rhzd9zYraMc', '2012-11-07', 'false', 'M', '7444 Reindahl Drive', '1940-09-01');
INSERT INTO PetOwner VALUES ('Idaline', 'Livy', 'lsherred2x@yolasite.com', 'H5tpeRglfG', '2017-06-20', 'false', 'F', '16 Eagle Crest Junction', '1998-10-31');
INSERT INTO PetOwner VALUES ('Kimberley', 'Lucille', 'lparriss2y@github.io', 'EznEKQ8npLKi', '2005-03-06', 'true', 'F', '59 Elka Terrace', '1947-07-09');
INSERT INTO PetOwner VALUES ('Jacobo', 'Valentijn', 'vhenriques2z@hubpages.com', '5HJWY8fu', '2020-05-13', 'false', 'M', '1467 Atwood Plaza', '1985-02-21');
INSERT INTO PetOwner VALUES ('Lyle', 'Terry', 'thedderly30@unc.edu', 'XlwsCHXbb', '2010-03-24', 'true', 'M', '16859 Bonner Crossing', '1953-06-08');
INSERT INTO PetOwner VALUES ('Clea', 'Nissie', 'ntommeo31@woothemes.com', 'hWTf923hVcOY', '2018-12-15', 'false', 'F', '05 Lighthouse Bay Plaza', '1946-08-29');
INSERT INTO PetOwner VALUES ('Ram', 'Forster', 'fdeem32@utexas.edu', 'gCc0OFY', '2018-03-26', 'true', 'M', '504 Schiller Junction', '1948-09-13');
INSERT INTO PetOwner VALUES ('Kordula', 'Kalina', 'kpottinger33@w3.org', 'JtBB8g1EtDyv', '2012-03-10', 'false', 'F', '68 Ridgeview Road', '1962-08-18');
INSERT INTO PetOwner VALUES ('Bell', 'Melosa', 'mking34@cargocollective.com', 'oeYuQQPDT5DB', '2017-08-29', 'false', 'F', '88 Moulton Street', '2013-11-15');
INSERT INTO PetOwner VALUES ('Freeland', 'Clayson', 'clangthorne35@chicagotribune.com', 'YiUKQAXd', '2002-10-18', 'false', 'M', '01123 Gale Parkway', '1981-03-28');
INSERT INTO PetOwner VALUES ('Roderigo', 'Nico', 'nquarlis36@imdb.com', 'JopvSV', '2016-08-21', 'true', 'M', '339 Hazelcrest Court', '1977-08-07');
INSERT INTO PetOwner VALUES ('Genny', 'Shawna', 'sklimochkin37@wufoo.com', 'bTjJ3l9EZ', '2006-10-22', 'false', 'F', '706 Manufacturers Crossing', '1971-02-06');
INSERT INTO PetOwner VALUES ('Jordanna', 'Maurizia', 'mwernher38@cafepress.com', 'inDhy9', '2016-03-27', 'false', 'F', '39 Westend Way', '2005-03-20');
INSERT INTO PetOwner VALUES ('Algernon', 'Ody', 'orobins39@bandcamp.com', '0W0m4k', '2002-01-28', 'true', 'M', '2 Pleasure Trail', '2008-06-04');
INSERT INTO PetOwner VALUES ('Tedd', 'Clyve', 'clearmont3a@mayoclinic.com', 'bfo2QFG', '2008-07-28', 'true', 'M', '808 Bluejay Terrace', '1990-02-26');
INSERT INTO PetOwner VALUES ('Palm', 'Edmund', 'esennett3b@yandex.ru', '2z1lPT', '2001-07-26', 'true', 'M', '5 Randy Center', '1988-12-26');
INSERT INTO PetOwner VALUES ('Lorita', 'Eolanda', 'efarguhar3c@yahoo.co.jp', 'msZ7Ns', '2009-03-14', 'false', 'F', '49208 Merchant Hill', '2000-04-23');
INSERT INTO PetOwner VALUES ('Hedwiga', 'Lelia', 'lheaney3d@slideshare.net', 'TpWkEGMEnT', '2018-02-26', 'true', 'F', '3 Starling Lane', '2017-05-10');
INSERT INTO PetOwner VALUES ('Markos', 'Sebastiano', 'sdurkin3e@kickstarter.com', 'Hoc7FjLlp85', '2016-07-09', 'false', 'M', '211 Dexter Hill', '2008-08-26');
INSERT INTO PetOwner VALUES ('Jerri', 'Elisha', 'eduncan3f@theatlantic.com', 'NN4YgDNwyl0v', '2008-03-12', 'false', 'M', '25 Oakridge Lane', '1954-11-17');
INSERT INTO PetOwner VALUES ('El', 'Dal', 'dverbeek3g@goo.ne.jp', 'ZTZnJtesoY6Y', '2008-11-16', 'true', 'M', '3315 Rutledge Park', '2011-05-18');
INSERT INTO PetOwner VALUES ('Konstance', 'Ambur', 'aseymer3h@bloomberg.com', 'tU9HuLraCZ', '2014-07-10', 'false', 'F', '5 Moland Circle', '1977-11-24');
INSERT INTO PetOwner VALUES ('Allin', 'Reuven', 'rmenendes3i@mit.edu', 'rWL5bea1CK', '2006-07-17', 'false', 'M', '10 Florence Alley', '2013-03-31');
INSERT INTO PetOwner VALUES ('Allen', 'Ives', 'icleiment3j@fc2.com', 'dICmkn', '2016-11-23', 'false', 'M', '45 Morning Lane', '2005-04-02');
INSERT INTO PetOwner VALUES ('Etienne', 'Zechariah', 'zmalin3k@netvibes.com', 'GZUovCmpEy', '2008-02-22', 'false', 'M', '783 Waubesa Drive', '2007-08-05');
INSERT INTO PetOwner VALUES ('Adrian', 'Jule', 'jaldiss3l@independent.co.uk', 'k5GOYLuJVR', '2013-01-11', 'false', 'M', '3962 Grasskamp Lane', '1964-06-08');
INSERT INTO PetOwner VALUES ('Valencia', 'Hanni', 'hbaddam3m@go.com', 'sfm2PPr15QTz', '2003-09-29', 'false', 'F', '2616 Northridge Center', '1947-07-19');
INSERT INTO PetOwner VALUES ('Waylen', 'Desmund', 'dgilbert3n@scientificamerican.com', 'QiGjBYTeH', '2016-05-31', 'false', 'M', '2 Crest Line Avenue', '1937-02-13');
INSERT INTO PetOwner VALUES ('Jere', 'Richie', 'rbruni3o@livejournal.com', '93JgbA7', '2020-07-16', 'false', 'M', '51 Burning Wood Park', '1942-11-24');
INSERT INTO PetOwner VALUES ('Ephrayim', 'Jedediah', 'jphelips3p@cnn.com', 'lXwDqu389dgN', '2010-08-16', 'false', 'M', '69 Clyde Gallagher Junction', '1937-02-26');
INSERT INTO PetOwner VALUES ('Barr', 'Willard', 'wjefferson3q@google.co.jp', 'ATnI8ORNqG', '2013-04-06', 'false', 'M', '26495 Garrison Park', '1971-06-06');
INSERT INTO PetOwner VALUES ('Issy', 'Larina', 'lconor3r@hp.com', 'aaf9qUmPQd', '2010-01-28', 'false', 'F', '8631 Nevada Center', '1971-03-22');
INSERT INTO PetOwner VALUES ('Christie', 'Diandra', 'dhaggis3s@dell.com', '0lekrK8b0pPB', '2010-06-25', 'false', 'F', '21962 Fuller Road', '1979-10-12');
INSERT INTO PetOwner VALUES ('Cris', 'Oberon', 'owalles3t@yolasite.com', 'zWnQnD6PLo', '2019-11-09', 'false', 'M', '563 Heffernan Street', '1957-03-30');
INSERT INTO PetOwner VALUES ('Lars', 'Itch', 'ibrunnen3u@webnode.com', 'mVi49i', '2001-10-14', 'false', 'M', '540 Stoughton Terrace', '1976-08-30');
INSERT INTO PetOwner VALUES ('Salvador', 'Davie', 'ddooley3v@devhub.com', 'pM3Dy912ntqq', '2001-02-20', 'false', 'M', '2 American Drive', '1941-06-18');
INSERT INTO PetOwner VALUES ('Monika', 'Lizbeth', 'ltocher3w@huffingtonpost.com', 'BKhyTDH0RgP', '2013-05-04', 'true', 'F', '2 Waywood Court', '2012-06-13');
INSERT INTO PetOwner VALUES ('Goldy', 'Doro', 'dbodicam3x@thetimes.co.uk', 'BHcbgxXPF', '2011-11-15', 'false', 'F', '4 Old Gate Point', '1987-12-10');
INSERT INTO PetOwner VALUES ('Lorry', 'Grove', 'gsammars3y@ycombinator.com', 'U9ZlURTlxL', '2016-09-20', 'true', 'M', '77730 Warrior Parkway', '2010-07-14');
INSERT INTO PetOwner VALUES ('Hannah', 'Allyce', 'adevaar3z@yahoo.co.jp', '27xNNg', '2013-09-21', 'false', 'F', '74286 Hallows Pass', '2013-12-07');
INSERT INTO PetOwner VALUES ('Adrienne', 'Bridgette', 'bgoddard40@mysql.com', 'CmzFFKFA', '2001-04-05', 'true', 'F', '579 School Crossing', '1995-12-03');
INSERT INTO PetOwner VALUES ('Bron', 'Rafael', 'rlepope42@google.com', 'xvCzNg', '2007-10-17', 'false', 'M', '88583 Northridge Crossing', '1979-05-01');
INSERT INTO PetOwner VALUES ('Kirby', 'Lanie', 'lmaudsley43@gizmodo.com', 'N6C8RYGgN', '2009-07-03', 'true', 'M', '0020 Monterey Lane', '2003-07-22');
INSERT INTO PetOwner VALUES ('Jonis', 'Miof mela', 'mvasilmanov44@amazon.de', 'TPh1yIczwJd', '2003-08-26', 'true', 'F', '3867 Anderson Circle', '1997-10-07');
INSERT INTO PetOwner VALUES ('Oralie', 'Korella', 'kwhitnell45@omniture.com', 'm29R1UN87w', '2010-09-04', 'false', 'F', '89590 Bunting Hill', '1931-04-09');
INSERT INTO PetOwner VALUES ('Josefa', 'Sarene', 'scudworth46@networksolutions.com', 'bZSesRVt', '2005-12-01', 'true', 'F', '34 Armistice Junction', '1948-05-19');
INSERT INTO PetOwner VALUES ('Adoree', 'Barbara-anne', 'bsteabler47@angelfire.com', 'bSliyAad4Hi', '2016-03-21', 'false', 'F', '6867 Cody Alley', '1984-05-18');
INSERT INTO PetOwner VALUES ('Packston', 'Tiebold', 'tbroster49@tinypic.com', '36VzF2X3', '2009-09-24', 'false', 'M', '8831 Atwood Road', '1936-12-11');
INSERT INTO PetOwner VALUES ('Kane', 'Luce', 'lcoppledike4a@ovh.net', 'eOWl3aure', '2003-04-02', 'false', 'M', '2 Mockingbird Road', '1947-03-10');
INSERT INTO PetOwner VALUES ('Wade', 'Mischa', 'mbraybrooke4b@archive.org', 'eOCvbbFD2z5', '2016-07-04', 'false', 'M', '4313 Charing Cross Trail', '1944-07-04');
INSERT INTO PetOwner VALUES ('Mae', 'Malorie', 'mrudham4c@utexas.edu', '1SAuYfUV4', '2012-02-03', 'false', 'F', '966 Magdeline Center', '2007-08-31');
INSERT INTO PetOwner VALUES ('Sigfrid', 'Raul', 'rlarmour4d@linkedin.com', '3t3ZqL', '2019-04-25', 'false', 'M', '13 Goodland Way', '2013-11-03');
INSERT INTO PetOwner VALUES ('Rhys', 'Gerardo', 'ghulke4e@apple.com', '7ZavgBY53w', '2001-11-14', 'true', 'M', '6 Nancy Avenue', '1971-01-18');
INSERT INTO PetOwner VALUES ('Morris', 'Bartolemo', 'bpeckitt4f@businessweek.com', 'W7oso9gZ', '2010-11-28', 'false', 'M', '41 Jenifer Circle', '2002-05-10');
INSERT INTO PetOwner VALUES ('Essy', 'Lishe', 'lmcivor4g@mozilla.org', 'eCWfjuACcn', '2012-02-15', 'false', 'F', '1010 Westridge Center', '1951-12-16');
INSERT INTO PetOwner VALUES ('Aubree', 'Caye', 'cgreeve4h@opera.com', 'f2dwBrFW', '2011-07-06', 'true', 'F', '4 Clyde Gallagher Way', '1986-09-09');
INSERT INTO PetOwner VALUES ('Sharia', 'Maddi', 'mjacke4i@goo.ne.jp', 'wNJGblP', '2001-04-27', 'false', 'F', '402 Kennedy Drive', '2009-06-04');
INSERT INTO PetOwner VALUES ('Taber', 'Conant', 'ckybbye4j@sina.com.cn', 't3mWZTK5Vlg', '2017-11-11', 'false', 'M', '5 Oxford Parkway', '1951-10-20');
INSERT INTO PetOwner VALUES ('Mortie', 'Lauritz', 'lfone4k@cocolog-nifty.com', 'O5zrBsf', '2019-02-17', 'false', 'M', '309 Maple Wood Center', '1930-12-10');
INSERT INTO PetOwner VALUES ('Amery', 'Klement', 'kfinci4l@networksolutions.com', 'qH3yeaYi', '2017-06-05', 'true', 'M', '72 Annamark Avenue', '1998-01-25');
INSERT INTO PetOwner VALUES ('Reinwald', 'Franky', 'fstocking4m@vkontakte.ru', 'dRXPhER', '2017-03-29', 'true', 'M', '2 Redwing Parkway', '1996-02-04');
INSERT INTO PetOwner VALUES ('Gianna', 'Tabbatha', 'tnewens4n@twitpic.com', 'C3ghgGckP8', '2003-02-03', 'false', 'F', '19487 Saint Paul Pass', '1998-05-22');
INSERT INTO PetOwner VALUES ('Laurence', 'Demetris', 'dblakiston4o@yellowpages.com', '6alNjmSU', '2002-07-05', 'false', 'M', '10 Bobwhite Way', '1971-12-01');
INSERT INTO PetOwner VALUES ('Alfie', 'Dorelle', 'dsleeny4p@hubpages.com', '5JZjNN', '2010-01-04', 'false', 'F', '9 Darwin Junction', '1996-07-19');
INSERT INTO PetOwner VALUES ('Willow', 'Laurel', 'lsybry4q@craigslist.org', 'ncGMQGPzEos', '2008-01-10', 'false', 'F', '6 Pearson Place', '1954-06-13');
INSERT INTO PetOwner VALUES ('Edythe', 'Jean', 'jfriar4r@archive.org', 'vGsNlawvLwF0', '2018-11-17', 'false', 'F', '22 Norway Maple Pass', '1947-10-02');
INSERT INTO PetOwner VALUES ('Micaela', 'Marie-jeanne', 'mcurrell4s@house.gov', 'n9IfeOUvTtRF', '2006-02-17', 'true', 'F', '320 Nobel Crossing', '1976-09-17');
INSERT INTO PetOwner VALUES ('Jemmie', 'Pam', 'pbamell4t@nhs.uk', 'nTdlQi9o', '2018-02-26', 'false', 'F', '33 Veith Point', '1960-06-11');
INSERT INTO PetOwner VALUES ('Jami', 'Philomena', 'pwheeliker4u@bloglines.com', 'JkMQehIw', '2008-09-02', 'true', 'F', '08 Stang Street', '2018-05-19');
INSERT INTO PetOwner VALUES ('Morly', 'Randell', 'rgudgeon4v@telegraph.co.uk', '11JI5PF4mcwo', '2003-07-01', 'true', 'M', '8296 Mandrake Pass', '1994-07-04');
INSERT INTO PetOwner VALUES ('Jacquetta', 'Lorrie', 'lsheering4w@cbslocal.com', '7tuXbxhGbMN', '2003-07-31', 'false', 'F', '8 Nova Circle', '2008-01-16');
INSERT INTO PetOwner VALUES ('Freddy', 'Catriona', 'clilian4x@jugem.jp', '5S1IYN0ExB', '2013-08-31', 'true', 'F', '8761 Coolidge Alley', '2014-02-16');
INSERT INTO PetOwner VALUES ('Pauly', 'Silvio', 'sgillatt4y@ezinearticles.com', 'LS9raubvCbV', '2013-10-06', 'true', 'M', '0567 Boyd Junction', '1936-06-22');
INSERT INTO PetOwner VALUES ('Bradan', 'Waylan', 'wmcanalley4z@github.com', 'FpBBddl', '2011-04-18', 'false', 'M', '457 Fairview Park', '1989-02-14');
INSERT INTO PetOwner VALUES ('Ansley', 'Roxy', 'rhelsdon50@unc.edu', 'YLEjY1fm', '2009-08-20', 'true', 'F', '98526 Sloan Circle', '1985-01-06');
INSERT INTO PetOwner VALUES ('Celka', 'Lydie', 'lgarfoot51@cloudflare.com', '5CivnfFQ', '2017-10-11', 'false', 'F', '662 Sunnyside Court', '2001-02-22');
INSERT INTO PetOwner VALUES ('Alfredo', 'Adlai', 'alomas52@theglobeandmail.com', '43Sypivsgp0q', '2006-12-09', 'true', 'M', '472 Clove Pass', '2018-10-10');
INSERT INTO PetOwner VALUES ('Rabbi', 'Lorens', 'lgarrelts53@scribd.com', 'JURglI', '2007-08-01', 'false', 'M', '1 Florence Center', '1955-11-27');
INSERT INTO PetOwner VALUES ('Maureene', 'Kirsten', 'kbatcheldor54@nih.gov', 'DJjq38AAXY', '2020-03-28', 'false', 'F', '687 Rowland Alley', '2009-07-20');
INSERT INTO PetOwner VALUES ('Odo', 'Teador', 'tlimb55@cloudflare.com', 'xB5erZH', '2008-09-08', 'true', 'M', '94851 Nevada Center', '1991-11-21');
INSERT INTO PetOwner VALUES ('Harlen', 'Ive', 'iyakubovics56@mashable.com', 'NeKrkvU8Fi2Z', '2009-09-25', 'false', 'M', '31977 Logan Place', '1970-11-14');
INSERT INTO PetOwner VALUES ('Maurizio', 'Edgard', 'eradbourn57@chronoengine.com', 's6nrwJv8tWU4', '2014-02-03', 'true', 'M', '19 Blackbird Lane', '1938-05-23');
INSERT INTO PetOwner VALUES ('Dre', 'Aundrea', 'anorthin58@columbia.edu', 'Lp5jqEI7o', '2008-11-14', 'true', 'F', '322 Saint Paul Place', '1943-01-05');
INSERT INTO PetOwner VALUES ('Emalee', 'Maxine', 'maddy59@pen.io', '1JQLgkbTt', '2009-10-08', 'true', 'F', '8945 Golden Leaf Junction', '2015-07-26');
INSERT INTO PetOwner VALUES ('Korey', 'Jacob', 'jrome5a@hatena.ne.jp', 'THOOOqKrvdaH', '2012-02-01', 'true', 'M', '4 Havey Terrace', '1985-05-07');
INSERT INTO PetOwner VALUES ('Kay', 'Carena', 'cbritland5b@craigslist.org', 'wYFib2QD', '2007-11-23', 'false', 'F', '98 Browning Plaza', '1954-11-21');
INSERT INTO PetOwner VALUES ('Chrysa', 'Bel', 'bdalligan5c@multiply.com', 'FpUqVUQpZBo8', '2017-12-14', 'false', 'F', '32701 Parkside Avenue', '1982-07-09');
INSERT INTO PetOwner VALUES ('Rudie', 'Iver', 'iwestern5d@nbcnews.com', 'mXIz4E', '2003-03-18', 'false', 'M', '773 Saint Paul Court', '1981-01-01');
INSERT INTO PetOwner VALUES ('Mignon', 'Marijo', 'mlodwick5e@simplemachines.org', 'VCoMKr', '2015-04-16', 'true', 'F', '523 Commercial Junction', '2005-02-12');
INSERT INTO PetOwner VALUES ('Jemie', 'Glenn', 'gcripwell5f@opensource.org', 'eaENEbjj', '2018-10-06', 'false', 'F', '5 Onsgard Avenue', '1958-11-02');
INSERT INTO PetOwner VALUES ('Ricki', 'Salim', 'slyste5g@domainmarket.com', '7RfBD4pumi0t', '2015-09-10', 'true', 'M', '9112 Spaight Park', '1988-05-02');
INSERT INTO PetOwner VALUES ('Kinsley', 'Hillery', 'hbaddiley5i@macromedia.com', 'l1D5vS', '2013-04-18', 'true', 'M', '4 Del Mar Avenue', '1995-07-12');
INSERT INTO PetOwner VALUES ('Rodolfo', 'Nero', 'nandresen5j@lycos.com', 'oTNgKgYAfVS', '2005-03-08', 'true', 'M', '547 Mallard Plaza', '1999-04-16');
INSERT INTO PetOwner VALUES ('Marion', 'Lionel', 'lcocke5k@tumblr.com', 'bj3YF2hX', '2013-08-20', 'false', 'M', '53 Myrtle Avenue', '2013-10-04');
INSERT INTO PetOwner VALUES ('Zacharia', 'Kirby', 'kliversley5l@slate.com', '08ku3La8X', '2003-09-08', 'false', 'M', '72 Nobel Road', '1985-09-02');
INSERT INTO PetOwner VALUES ('Ike', 'Dexter', 'dkorn5m@cornell.edu', 'g8YwMYbWGdm', '2016-11-25', 'false', 'M', '028 Wayridge Park', '1987-05-17');
INSERT INTO PetOwner VALUES ('Tallia', 'Horatia', 'hdibdall5n@instagram.com', 'ALn5MkWGLN', '2006-01-14', 'true', 'F', '13 Holmberg Road', '1965-10-28');
INSERT INTO PetOwner VALUES ('Catharine', 'Leanor', 'lsamwayes5o@state.gov', 'mnUGzxHo', '2003-09-10', 'true', 'F', '9993 Scott Alley', '1959-02-17');
INSERT INTO PetOwner VALUES ('Inessa', 'Christa', 'cwatting5p@ted.com', 'TKpK4o2Pu', '2001-09-03', 'false', 'F', '7 Transport Lane', '1947-01-02');
INSERT INTO PetOwner VALUES ('Vittoria', 'Demetria', 'dpedler5r@unc.edu', 'ApMsehL', '2015-09-20', 'false', 'F', '88 Kipling Park', '1931-07-15');
INSERT INTO PetOwner VALUES ('Wilhelm', 'Leicester', 'lbridgen5s@sourceforge.net', 'p8EhIK', '2018-09-23', 'true', 'M', '1 Bultman Alley', '2008-07-23');
INSERT INTO PetOwner VALUES ('Abbott', 'Paxon', 'pughi5t@stumbleupon.com', '8G5CT65', '2012-02-11', 'false', 'M', '912 Melvin Hill', '1960-05-20');
INSERT INTO PetOwner VALUES ('Ofelia', 'Kalindi', 'kforstall5u@com.com', 'RKt7Dj7RDCu3', '2006-02-10', 'true', 'F', '64259 Westport Road', '1981-07-30');
INSERT INTO PetOwner VALUES ('Merrill', 'Doretta', 'dsellens5v@jalbum.net', 'B3FfWPG2k', '2004-05-20', 'true', 'F', '7 Dottie Street', '2014-12-31');
INSERT INTO PetOwner VALUES ('Paulina', 'Tommy', 'tzorzin5w@seesaa.net', '0nTar0', '2004-12-07', 'true', 'F', '55669 American Lane', '1995-10-11');
INSERT INTO PetOwner VALUES ('Krissy', 'Valerie', 'vlacotte5x@oakley.com', 'GFCR2jdN5qO', '2002-11-30', 'false', 'F', '83528 Fallview Road', '2010-01-26');
INSERT INTO PetOwner VALUES ('Judah', 'Jesse', 'jnormant5y@mit.edu', 'J2nS8h', '2003-01-17', 'true', 'M', '5278 Vahlen Plaza', '1948-07-23');
INSERT INTO PetOwner VALUES ('Sandra', 'Jennette', 'jpilkinton5z@google.com.hk', '1vLyxz', '2007-03-09', 'false', 'F', '24 Dryden Street', '1977-10-29');
INSERT INTO PetOwner VALUES ('Loralyn', 'Bev', 'bstollery60@elpais.com', '326naYZk', '2006-08-20', 'false', 'F', '217 Golden Leaf Avenue', '1981-08-06');
INSERT INTO PetOwner VALUES ('Tyler', 'Paxton', 'pbedberry61@umn.edu', 'qG4aFYjUjB0', '2006-04-08', 'true', 'M', '753 Hauk Terrace', '1965-04-01');
INSERT INTO PetOwner VALUES ('Suzi', 'Adelle', 'abaddeley62@sina.com.cn', 'uRrxxtY9', '2008-10-12', 'false', 'F', '9154 Fordem Pass', '1942-08-14');
INSERT INTO PetOwner VALUES ('Mychal', 'Val', 'vrameaux63@hatena.ne.jp', '2q3NFvdpt', '2002-02-22', 'true', 'M', '36 Springs Avenue', '2012-04-06');
INSERT INTO PetOwner VALUES ('Eddie', 'Cross', 'cgennrich64@usnews.com', 'w6oysG9Z', '2019-06-24', 'true', 'M', '88386 Kinsman Drive', '1975-04-17');
INSERT INTO PetOwner VALUES ('Hilarius', 'Derrik', 'dfostersmith65@meetup.com', '4mGnGCdrbcjB', '2012-05-07', 'true', 'M', '0 Scoville Way', '1934-11-21');
INSERT INTO PetOwner VALUES ('Caroljean', 'Annecorinne', 'apischel66@networkadvertising.org', 'S9LyZ1VD8ZD', '2010-05-15', 'false', 'F', '9 Oak Terrace', '2017-03-29');
INSERT INTO PetOwner VALUES ('Ernesta', 'Tamar', 'tlamplough67@hibu.com', 'HV42oZ', '2015-06-05', 'false', 'F', '9 Lakewood Junction', '1945-03-18');
INSERT INTO PetOwner VALUES ('Clarita', 'Kathryn', 'kdabinett68@qq.com', 'jPel3S', '2005-12-28', 'false', 'F', '54110 Pearson Road', '2012-12-27');
INSERT INTO PetOwner VALUES ('Loree', 'Elnore', 'erosita69@army.mil', 'XxlxYgT', '2010-06-11', 'false', 'F', '16 Service Plaza', '1973-09-27');
INSERT INTO PetOwner VALUES ('Fonz', 'Gregg', 'gmchirrie6a@bizjournals.com', 'wHMHjuIi0mY', '2017-11-03', 'false', 'M', '585 Sycamore Court', '1945-01-26');
INSERT INTO PetOwner VALUES ('Duff', 'Otto', 'omcure6b@wiley.com', 'xHxrVCfB', '2006-08-23', 'false', 'M', '91792 Veith Street', '1953-03-10');
INSERT INTO PetOwner VALUES ('Carlynne', 'Jeane', 'jtapner6c@networkadvertising.org', 'sm0No3BNu', '2020-07-05', 'true', 'F', '41 Milwaukee Place', '2019-07-24');
INSERT INTO PetOwner VALUES ('Dina', 'Shanon', 'sbrazur6d@simplemachines.org', 'mQwYHD0', '2018-11-05', 'false', 'F', '15 Veith Parkway', '1960-06-05');
INSERT INTO PetOwner VALUES ('Rasla', 'Whitney', 'wjefferd6e@github.com', 'HXfowQ5B', '2011-07-28', 'true', 'F', '4436 Little Fleur Park', '2010-10-03');
INSERT INTO PetOwner VALUES ('Nickie', 'Isacco', 'ikeer6f@ucoz.ru', 'HssSVQOy', '2002-01-09', 'false', 'M', '62227 Northwestern Trail', '1981-07-24');
INSERT INTO PetOwner VALUES ('Lexie', 'Guinevere', 'gwalby6g@spotify.com', 'SFOiRBsry04', '2002-01-13', 'false', 'F', '6 Basil Hill', '1953-02-24');
INSERT INTO PetOwner VALUES ('Wilbert', 'Donal', 'dwhytock6h@japanpost.jp', 'DE8J0O2kC', '2003-07-22', 'true', 'M', '8 Cardinal Park', '1982-10-29');
INSERT INTO PetOwner VALUES ('Aurie', 'Stacee', 'strusslove6i@washingtonpost.com', 'uZpvkJe', '2011-03-02', 'false', 'F', '135 Charing Cross Crossing', '2000-12-18');
INSERT INTO PetOwner VALUES ('Belita', 'Catriona', 'cfarthin6j@blogtalkradio.com', 'JVbWoc5s', '2019-01-01', 'true', 'F', '3400 Mallory Trail', '1945-01-11');
INSERT INTO PetOwner VALUES ('Cristobal', 'Jonathan', 'jsearight6k@deviantart.com', 'NWKbkPYETRLm', '2004-02-14', 'true', 'M', '7 Shelley Way', '1973-12-20');
INSERT INTO PetOwner VALUES ('Alta', 'Bridgette', 'battaway6l@amazonaws.com', '4VSOVjJU', '2002-04-19', 'true', 'F', '5 High Crossing Junction', '1968-09-28');
INSERT INTO PetOwner VALUES ('Earlie', 'Walker', 'wfilippello6m@indiegogo.com', 'nUmc0IOfHP', '2006-09-12', 'false', 'M', '15717 5th Parkway', '1993-06-15');
INSERT INTO PetOwner VALUES ('Tatum', 'Idell', 'igiacopello6n@time.com', 'Rt46jF', '2011-04-01', 'true', 'F', '279 Center Trail', '1932-03-07');
INSERT INTO PetOwner VALUES ('Decca', 'Logan', 'lmalser6o@addtoany.com', 'YlGPBtH', '2003-03-05', 'false', 'M', '6695 Oriole Pass', '1971-08-22');
INSERT INTO PetOwner VALUES ('Thorstein', 'Marvin', 'msnarie6p@geocities.jp', '63LGZdOwhk', '2013-08-02', 'false', 'M', '0 Express Point', '1995-11-03');
INSERT INTO PetOwner VALUES ('Carlin', 'Leo', 'lfreeburn6q@joomla.org', '6ll7yicrGIie', '2014-01-03', 'true', 'M', '7140 Delaware Trail', '1935-03-06');
INSERT INTO PetOwner VALUES ('Rodina', 'Charissa', 'cbraunter6r@blogger.com', 'ibI5yy', '2010-12-30', 'false', 'F', '52723 Knutson Parkway', '1935-12-24');
INSERT INTO PetOwner VALUES ('Byrom', 'Kelbee', 'kfoldes6s@imgur.com', 'iFnYKsPytThx', '2008-01-09', 'false', 'M', '2 Magdeline Junction', '1939-08-02');
INSERT INTO PetOwner VALUES ('Phillie', 'Chelsey', 'cbohman6t@whitehouse.gov', 'xBXtYpP', '2003-10-15', 'false', 'F', '41 Carioca Place', '2014-07-17');
INSERT INTO PetOwner VALUES ('Bernete', 'Karlyn', 'kgabits6u@chicagotribune.com', 'NBa6gKX', '2013-04-29', 'false', 'F', '5671 Reinke Junction', '1960-11-08');
INSERT INTO PetOwner VALUES ('Rachael', 'Lenee', 'lattride6v@google.pl', '6lamRiD', '2017-08-22', 'false', 'F', '58 Helena Center', '1950-12-26');
INSERT INTO PetOwner VALUES ('Maurice', 'Corbie', 'cmandres6w@seesaa.net', 'CEdzr4B', '2002-09-10', 'true', 'M', '0 Oak Valley Place', '1983-07-17');
INSERT INTO PetOwner VALUES ('Carmina', 'Marlie', 'mcolborn6x@123-reg.co.uk', '9Q3oM74q27', '2002-12-18', 'true', 'F', '04 Merrick Hill', '1952-10-02');
INSERT INTO PetOwner VALUES ('Margi', 'Ailsun', 'apoter6y@paginegialle.it', 'f0QB0U', '2004-07-04', 'false', 'F', '0 Mcbride Drive', '2005-02-15');
INSERT INTO PetOwner VALUES ('Francklin', 'Flin', 'fcawdell6z@trellian.com', 'M69QNLOkev', '2009-07-03', 'false', 'M', '32 Huxley Terrace', '1988-11-11');
INSERT INTO PetOwner VALUES ('Leonanie', 'Editha', 'emerali70@ehow.com', 'TphVZP', '2011-06-23', 'true', 'F', '7725 Browning Avenue', '2003-12-22');
INSERT INTO PetOwner VALUES ('Doralynn', 'Antonia', 'apfeffle71@csmonitor.com', '4Iu2xHtg0c', '2002-04-19', 'false', 'F', '0820 Sutherland Alley', '1968-03-07');
INSERT INTO PetOwner VALUES ('Wells', 'Tobias', 'ttillot72@webs.com', 'SeSWYW', '2008-02-03', 'false', 'M', '7 Lawn Trail', '1979-04-17');
INSERT INTO PetOwner VALUES ('Bill', 'Charleen', 'cmonck73@cargocollective.com', 'eL9WDHGL', '2013-06-23', 'true', 'F', '98 Gina Crossing', '2012-04-21');
INSERT INTO PetOwner VALUES ('Peg', 'Ardyce', 'arennocks74@ftc.gov', 'Byk7fm', '2008-03-09', 'true', 'F', '7938 Shoshone Street', '1936-07-04');
INSERT INTO PetOwner VALUES ('Dorthy', 'Arlyn', 'ahyman75@timesonline.co.uk', 'e0fjUnd131', '2006-02-07', 'true', 'F', '2 Colorado Park', '1953-01-22');
INSERT INTO PetOwner VALUES ('Cobbie', 'Merell', 'mpeers76@dropbox.com', 'AAfAMJ', '2004-06-22', 'true', 'M', '03 Lawn Point', '1956-12-10');
INSERT INTO PetOwner VALUES ('Tyson', 'Conney', 'cpigdon77@marriott.com', 'XGogTTGz', '2002-12-22', 'true', 'M', '56 Kropf Point', '1962-06-28');
INSERT INTO PetOwner VALUES ('Rosana', 'Layney', 'lcorten78@unesco.org', 'ucnsNr8o', '2016-03-24', 'true', 'F', '5 Walton Avenue', '2018-05-29');
INSERT INTO PetOwner VALUES ('Pip', 'Claudius', 'cbatrip79@samsung.com', 'dLMnTw', '2015-06-06', 'true', 'M', '15 Erie Avenue', '1936-05-06');
INSERT INTO PetOwner VALUES ('Nadine', 'Georgeanne', 'gcambden7a@timesonline.co.uk', 'VNnsw1', '2017-06-25', 'true', 'F', '02 Melvin Place', '1946-07-01');
INSERT INTO PetOwner VALUES ('Brana', 'Charmion', 'ccanellas7b@arstechnica.com', 'RGy8mccoyjC', '2014-12-21', 'true', 'F', '40906 Reindahl Avenue', '2015-01-28');
INSERT INTO PetOwner VALUES ('Eberhard', 'Yorgo', 'ytowsey7c@google.fr', 'Ond6oMI', '2013-05-26', 'true', 'M', '3 Brown Court', '2013-12-08');
INSERT INTO PetOwner VALUES ('Annice', 'Jermaine', 'jbelden7d@addtoany.com', 'BQcni1sEy', '2007-04-15', 'true', 'F', '02 North Plaza', '1943-11-04');
INSERT INTO PetOwner VALUES ('Tiffy', 'Ingunna', 'igittis7e@freewebs.com', 'XvHpjdNaG2V', '2014-11-22', 'false', 'F', '657 Nova Place', '1934-11-16');
INSERT INTO PetOwner VALUES ('Edin', 'Marjorie', 'mdibb7f@uol.com.br', 'A5FAl11Ia', '2016-06-20', 'false', 'F', '647 Cherokee Plaza', '1935-06-07');
INSERT INTO PetOwner VALUES ('Nicky', 'Milena', 'mstead7g@com.com', 'xeg722VY', '2017-09-04', 'false', 'F', '8076 Morningstar Parkway', '1963-02-23');
INSERT INTO PetOwner VALUES ('Emerson', 'Ulberto', 'usweatland7h@deviantart.com', 'sUPGiKim3tR', '2018-10-20', 'true', 'M', '591 Stang Terrace', '1941-10-03');
INSERT INTO PetOwner VALUES ('Reina', 'Constantine', 'cnutty7i@wikimedia.org', '5wXyb82k9Y', '2005-11-19', 'false', 'F', '568 Green Ridge Junction', '1953-05-25');
INSERT INTO PetOwner VALUES ('Blake', 'Terence', 'tkaines7j@typepad.com', 'zc67XUwHlX', '2012-04-08', 'false', 'M', '21 Valley Edge Hill', '1935-06-25');
INSERT INTO PetOwner VALUES ('Pepito', 'Ulberto', 'uvasilmanov7k@disqus.com', 'HTB7IOLgIAXe', '2001-03-17', 'false', 'M', '8 Blackbird Center', '2014-07-17');
INSERT INTO PetOwner VALUES ('Car', 'Emmit', 'ebogays7l@time.com', 'BFcq4ZAslwW', '2008-05-21', 'true', 'M', '872 Tennessee Plaza', '2008-12-19');
INSERT INTO PetOwner VALUES ('Alisha', 'Atlanta', 'aclemintoni7m@cargocollective.com', 'Xj7rriBbUv', '2004-09-09', 'false', 'F', '35629 Kenwood Road', '2011-12-07');
INSERT INTO PetOwner VALUES ('Chiarra', 'Ryann', 'rverdon7n@51.la', '8EYJuzdWrV', '2001-10-14', 'false', 'F', '66 Amoth Circle', '2010-06-23');
INSERT INTO PetOwner VALUES ('Richmond', 'Abe', 'akilgrew7o@amazon.co.jp', 'BsQoAnP2c3BE', '2007-04-08', 'true', 'M', '403 Southridge Avenue', '1978-09-06');
INSERT INTO PetOwner VALUES ('Nerti', 'Adelice', 'ablenkensop7p@marketwatch.com', 'IgCwWI5gZ', '2003-05-27', 'false', 'F', '700 Bobwhite Court', '1996-08-23');
INSERT INTO PetOwner VALUES ('Cleve', 'Berny', 'bbracey7q@mediafire.com', 'xwn0paWm', '2011-02-08', 'true', 'M', '25484 Beilfuss Trail', '2016-02-16');
INSERT INTO PetOwner VALUES ('Hubey', 'Kristopher', 'kboddis7s@alibaba.com', 'u7Q32b0wu4Y', '2012-08-15', 'true', 'M', '1 Burrows Junction', '2015-05-07');
INSERT INTO PetOwner VALUES ('Alisun', 'Bili', 'bchapman7t@xinhuanet.com', 'Ehgj3sQUCtbK', '2008-08-17', 'true', 'F', '486 Quincy Point', '1957-03-24');
INSERT INTO PetOwner VALUES ('Andonis', 'Laurent', 'lsikorski7u@twitpic.com', '4XPaXQilHm', '2008-12-23', 'true', 'M', '6180 Kenwood Parkway', '2003-01-07');
INSERT INTO PetOwner VALUES ('Harry', 'Gothart', 'gruffey7v@networkadvertising.org', 'nyQdFD7', '2008-09-13', 'true', 'M', '4594 Laurel Junction', '1965-03-20');
INSERT INTO PetOwner VALUES ('Rebekah', 'Cami', 'ckerrod7w@addtoany.com', 'eRTWCq2', '2007-06-15', 'false', 'F', '8 Texas Parkway', '1995-02-12');
INSERT INTO PetOwner VALUES ('Alfonse', 'Kalil', 'kallridge7x@bravesites.com', 'V3cAFiL', '2013-09-07', 'true', 'M', '525 Main Drive', '1975-01-01');
INSERT INTO PetOwner VALUES ('Reggis', 'Reube', 'rfreer7y@nih.gov', '27XraKQc', '2020-04-13', 'false', 'M', '33 Dawn Drive', '1990-09-06');
INSERT INTO PetOwner VALUES ('Norah', 'Kaila', 'kpfeffle7z@about.me', 'sHDd8Sq', '2002-07-11', 'true', 'F', '809 Artisan Alley', '2018-11-09');
INSERT INTO PetOwner VALUES ('Hulda', 'Evelina', 'egosdin80@comsenz.com', 'nA0ripdzAt3', '2001-05-19', 'false', 'F', '4335 Oxford Park', '2019-12-10');
INSERT INTO PetOwner VALUES ('Bette-ann', 'Delphine', 'dbuggs81@hao123.com', 'm7yZ7sOk', '2008-06-15', 'true', 'F', '965 South Crossing', '2020-02-18');
INSERT INTO PetOwner VALUES ('Hart', 'Garreth', 'gshipperbottom82@nature.com', 'cvJ4POv', '2020-04-03', 'false', 'M', '48 Pleasure Lane', '2005-03-16');
INSERT INTO PetOwner VALUES ('Raleigh', 'Lanie', 'lmcnamee83@samsung.com', 'wjtHav4E1hE', '2001-02-06', 'true', 'M', '78175 Washington Way', '2009-02-04');
INSERT INTO PetOwner VALUES ('Pietra', 'Valery', 'viwanczyk84@nps.gov', 'rLWOv6cc', '2011-08-30', 'true', 'F', '2171 Blaine Junction', '2014-07-27');
INSERT INTO PetOwner VALUES ('Odey', 'Val', 'vdoig85@google.com', 'vAwRDhH5w1', '2015-02-03', 'false', 'M', '219 Homewood Crossing', '1934-09-15');
INSERT INTO PetOwner VALUES ('Queenie', 'Berte', 'bdinapoli86@weather.com', 'vyW21cGIFq', '2014-07-15', 'true', 'F', '00096 Roth Circle', '1974-06-20');
INSERT INTO PetOwner VALUES ('Peyton', 'Yard', 'ydeakan87@canalblog.com', 'St2Bkc', '2016-12-26', 'false', 'M', '7 Barnett Lane', '1987-07-06');
INSERT INTO PetOwner VALUES ('Adam', 'Guido', 'gwelbelove88@miitbeian.gov.cn', 'YaGFMrQcfQil', '2015-08-20', 'true', 'M', '4 Scofield Junction', '1961-09-13');
INSERT INTO PetOwner VALUES ('Paulie', 'Lalo', 'larchbold89@hatena.ne.jp', 'JFgARHg', '2004-10-07', 'false', 'M', '18 Susan Crossing', '1959-12-12');
INSERT INTO PetOwner VALUES ('Lucky', 'Milena', 'mastlet8a@fda.gov', 'cvlDvtB', '2016-04-18', 'false', 'F', '6 New Castle Park', '1965-09-15');
INSERT INTO PetOwner VALUES ('Gwendolin', 'Eulalie', 'edeny8b@mit.edu', '4SjPcsxQO10', '2020-08-11', 'true', 'F', '717 Haas Hill', '2007-03-12');
INSERT INTO PetOwner VALUES ('Sloan', 'Yank', 'ygarth8c@zimbio.com', 'JRO7G20', '2012-02-15', 'false', 'M', '39 Fremont Court', '1974-03-06');
INSERT INTO PetOwner VALUES ('Frankie', 'Lancelot', 'lbrierley8d@printfriendly.com', 'PnotJvQQDPoJ', '2020-05-11', 'true', 'M', '6 Express Parkway', '1959-11-04');
INSERT INTO PetOwner VALUES ('Randie', 'Agnola', 'astranio8e@webs.com', '5u5KIcW4xq', '2016-06-09', 'true', 'F', '5157 Sunnyside Court', '1967-06-11');
INSERT INTO PetOwner VALUES ('Ulberto', 'Kelvin', 'kmidgley8f@sfgate.com', 'uXI9JrM', '2001-07-04', 'true', 'M', '61482 Anhalt Point', '2009-03-31');
INSERT INTO PetOwner VALUES ('Carmel', 'Thekla', 'tcopperwaite8g@ezinearticles.com', 'y9nlArizD', '2008-01-07', 'false', 'F', '8694 Farwell Pass', '1990-11-20');
INSERT INTO PetOwner VALUES ('Cathy', 'Daphna', 'drisom8h@vk.com', '4cGdXYv', '2003-06-26', 'true', 'F', '41377 School Point', '1963-10-14');
INSERT INTO PetOwner VALUES ('Homer', 'Gran', 'gbrede8i@dmoz.org', 'yJ97zyy52am', '2008-11-11', 'false', 'M', '16 Luster Junction', '1948-05-08');
INSERT INTO PetOwner VALUES ('Yolanthe', 'Tanya', 'tstagg8j@ocn.ne.jp', '5J1s47wy', '2020-07-28', 'true', 'F', '71113 Maple Wood Center', '2016-01-09');
INSERT INTO PetOwner VALUES ('Axel', 'Yorgo', 'yhorrod8k@cdbaby.com', 'jLNNFZgOa', '2011-01-25', 'false', 'M', '4 Bowman Junction', '1981-02-24');
INSERT INTO PetOwner VALUES ('Lilllie', 'Helsa', 'hrichly8l@home.pl', 'Wa7EvPXqeL7', '2004-11-22', 'true', 'F', '02769 Farwell Way', '1940-01-10');
INSERT INTO PetOwner VALUES ('Richart', 'Trumann', 'tearlam8m@creativecommons.org', 'Fk73qrix3JT8', '2002-05-15', 'true', 'M', '36 Darwin Avenue', '1954-04-09');
INSERT INTO PetOwner VALUES ('Felicio', 'Drud', 'ddaymont8n@theatlantic.com', '4lygrc', '2010-12-02', 'false', 'M', '1 Manitowish Alley', '1968-11-07');
INSERT INTO PetOwner VALUES ('Harriett', 'Sonia', 'sfountaine8o@unesco.org', 'Thmgqw1', '2015-04-10', 'false', 'F', '6764 Merrick Drive', '1945-10-27');
INSERT INTO PetOwner VALUES ('Kitti', 'Aliza', 'akellough8p@tripadvisor.com', 'FNkCIJnfjq', '2015-11-21', 'false', 'F', '964 Norway Maple Drive', '1947-05-16');
INSERT INTO PetOwner VALUES ('Jerry', 'Ashley', 'adudmarsh8q@marriott.com', 'gNhKBci', '2020-06-21', 'true', 'M', '46770 Barby Court', '1931-10-15');
INSERT INTO PetOwner VALUES ('Rebe', 'Bernetta', 'bximenez8r@webnode.com', 'KQwRwi', '2006-04-08', 'true', 'F', '39307 Ridge Oak Terrace', '1968-09-01');
INSERT INTO PetOwner VALUES ('Leelah', 'Honey', 'hroseman8s@jimdo.com', 'pBAUGdvt', '2006-01-28', 'false', 'F', '1231 Bluestem Plaza', '1995-06-15');
INSERT INTO PetOwner VALUES ('Ethe', 'Duky', 'dmccartan8t@elpais.com', 'nZIOSNp', '2013-08-20', 'true', 'M', '28 Mandrake Lane', '1955-07-27');
INSERT INTO PetOwner VALUES ('Sol', 'Elnar', 'epennigar8u@t.co', 'rEcOfxjd', '2004-06-19', 'true', 'M', '0 Caliangt Center', '1991-03-24');
INSERT INTO PetOwner VALUES ('Toby', 'Dame', 'ddegoey8v@msn.com', '3j2icUoUbh', '2016-07-30', 'false', 'M', '69 Monica Plaza', '1931-03-22');
INSERT INTO PetOwner VALUES ('Maddalena', 'Luce', 'lpottes8w@vinaora.com', 'XsJER0twMmVB', '2017-11-24', 'true', 'F', '31716 5th Crossing', '1983-05-10');
INSERT INTO PetOwner VALUES ('Kare', 'Vida', 'vtousey8x@hhs.gov', 'Jll1QXc', '2014-07-11', 'false', 'F', '083 Charing Cross Point', '1997-05-21');
INSERT INTO PetOwner VALUES ('Huntley', 'Lodovico', 'lcorrea8z@arizona.edu', 'd3o9Qy7TJMwt', '2016-12-04', 'true', 'M', '48894 Oak Valley Pass', '2008-05-21');
INSERT INTO PetOwner VALUES ('Trudy', 'Cecelia', 'cstitcher90@infoseek.co.jp', 'Zd3cKaNa', '2002-08-14', 'true', 'F', '1 Crescent Oaks Terrace', '1982-06-28');
INSERT INTO PetOwner VALUES ('Janey', 'Milzie', 'mdikelin91@who.int', 'fk1hz1', '2009-08-26', 'false', 'F', '2 Swallow Parkway', '2015-10-27');
INSERT INTO PetOwner VALUES ('Janek', 'Parker', 'pstormouth92@smh.com.au', 'OnmtKtq1eCS', '2020-05-11', 'true', 'M', '26 Anhalt Drive', '1985-12-22');
INSERT INTO PetOwner VALUES ('Blondelle', 'Gabie', 'gchilton93@phoca.cz', 'h59yWGs8', '2018-04-13', 'false', 'F', '411 Nobel Place', '1985-10-21');
INSERT INTO PetOwner VALUES ('Dannie', 'Livvyy', 'ltett94@gov.uk', 'UytrhG1io4JT', '2001-01-10', 'false', 'F', '99 Manley Plaza', '1969-03-20');
INSERT INTO PetOwner VALUES ('Alejandra', 'Adah', 'ablanden95@apache.org', 'sgQ7hzlc0', '2005-03-03', 'false', 'F', '86891 Hauk Place', '2002-02-24');
INSERT INTO PetOwner VALUES ('Yolane', 'Marquita', 'mposnette96@pinterest.com', '1SY3upZfh1', '2002-08-28', 'true', 'F', '4724 Summit Pass', '1969-11-26');
INSERT INTO PetOwner VALUES ('Ad', 'Delano', 'dkleinplatz97@godaddy.com', 'V8izGFiUsW', '2002-06-04', 'true', 'M', '80628 Crescent Oaks Terrace', '1956-09-23');
INSERT INTO PetOwner VALUES ('Tully', 'Lisle', 'larmin98@exblog.jp', '3wqYdSFPcK', '2012-11-08', 'false', 'M', '1 Mcbride Hill', '1974-06-01');
INSERT INTO PetOwner VALUES ('Florina', 'Silvie', 'stanfield99@blogspot.com', 'UXpjgIY', '2012-11-21', 'false', 'F', '325 Fairfield Hill', '1990-06-06');
INSERT INTO PetOwner VALUES ('Wit', 'Dew', 'dtolworthy9a@goo.gl', 'zUA040', '2019-10-21', 'true', 'M', '58 Forest Run Junction', '1944-12-22');
INSERT INTO PetOwner VALUES ('Zelma', 'Lauralee', 'lstorres9b@state.gov', 'q3yPVI60bRHQ', '2014-08-06', 'false', 'F', '20 Milwaukee Road', '2008-11-01');
INSERT INTO PetOwner VALUES ('Merrielle', 'Jillane', 'jmarians9c@nytimes.com', 'wQD6tMyNqaPF', '2016-12-05', 'false', 'F', '602 Jana Plaza', '1985-05-03');
INSERT INTO PetOwner VALUES ('Rubin', 'Rainer', 'rdeinert9d@creativecommons.org', 'f2bS5Ov', '2003-04-16', 'true', 'M', '9 Killdeer Court', '1964-08-23');
INSERT INTO PetOwner VALUES ('Arlyne', 'Charlot', 'cpailin9e@macromedia.com', 'HuXWzqc', '2006-01-14', 'true', 'F', '68610 Meadow Ridge Pass', '1949-04-15');
INSERT INTO PetOwner VALUES ('Jocelyn', 'Annora', 'atrouel9f@vimeo.com', 'hoFZphlY7', '2016-12-11', 'false', 'F', '17 Kim Park', '1944-01-16');
INSERT INTO PetOwner VALUES ('Quincey', 'Kaleb', 'khowland9g@nytimes.com', '8nqwZCiX0zg', '2010-04-11', 'true', 'M', '71759 Tennessee Lane', '1953-04-25');
INSERT INTO PetOwner VALUES ('Virgil', 'Kelsey', 'kplank9h@fema.gov', 'onEQI6P', '2003-05-28', 'false', 'M', '88301 Green Drive', '2013-03-28');
INSERT INTO PetOwner VALUES ('Morissa', 'Tabina', 'tgreenshields9i@hugedomains.com', 'smhIk3JDYKiF', '2010-08-23', 'false', 'F', '726 Mandrake Alley', '1992-12-25');
INSERT INTO PetOwner VALUES ('Ame', 'Jo-anne', 'jcraw9j@wix.com', 'AHlIAu', '2008-03-18', 'true', 'F', '3 Lotheville Court', '1953-04-13');
INSERT INTO PetOwner VALUES ('Consuelo', 'Mame', 'mmarmyon9k@alexa.com', '44Ew8U', '2012-11-04', 'false', 'F', '724 Carpenter Hill', '1992-09-01');
INSERT INTO PetOwner VALUES ('Alisander', 'Pernell', 'psainz9l@edublogs.org', 'L2gkst', '2006-06-04', 'true', 'M', '407 Cordelia Street', '2018-03-25');
INSERT INTO PetOwner VALUES ('Avrit', 'Agnes', 'ahadden9m@stumbleupon.com', 'FZE274Xk', '2015-07-11', 'true', 'F', '53 Schmedeman Park', '1951-09-29');
INSERT INTO PetOwner VALUES ('Reed', 'Dalt', 'dstoyle9n@tripadvisor.com', 'o0rnK51P', '2005-01-04', 'false', 'M', '4 Thackeray Circle', '1936-12-15');
INSERT INTO PetOwner VALUES ('Vita', 'Jaquelyn', 'jbautiste9o@pinterest.com', 'tVqeHFgEw9eE', '2017-01-12', 'false', 'F', '8512 Northfield Parkway', '1960-07-11');
INSERT INTO PetOwner VALUES ('Afton', 'Junette', 'jgowdridge9p@comsenz.com', 'xnhvvdgLmt6t', '2003-08-24', 'true', 'F', '90288 Gale Street', '1938-08-24');
INSERT INTO PetOwner VALUES ('Welsh', 'Chrisse', 'cbidgod9q@sun.com', 'dg9gNlmbm', '2019-03-19', 'true', 'M', '1 Meadow Ridge Place', '1952-08-20');
INSERT INTO PetOwner VALUES ('Isidoro', 'Alfonso', 'alacrouts9r@networkadvertising.org', 'sfHthYPbci', '2013-11-28', 'true', 'M', '65472 West Junction', '1999-06-19');
INSERT INTO PetOwner VALUES ('Cammi', 'Ariel', 'aodriscoll9s@scribd.com', 'fMl8el', '2011-08-08', 'true', 'F', '95 Corben Alley', '1961-10-24');
INSERT INTO PetOwner VALUES ('Jeannie', 'Sibyl', 'stofanini9t@mtv.com', '063HffKxImd', '2012-04-12', 'false', 'F', '2164 Southridge Hill', '2007-01-07');
INSERT INTO PetOwner VALUES ('Essa', 'Codie', 'crivitt9u@cisco.com', 'E1vOTr', '2001-11-13', 'false', 'F', '32 Ridgeway Terrace', '1946-09-05');
INSERT INTO PetOwner VALUES ('Elroy', 'Gasparo', 'gocuddie9v@tumblr.com', 'MrtPRU1Ceh', '2013-07-04', 'false', 'M', '4673 Green Alley', '1958-08-12');
INSERT INTO PetOwner VALUES ('Nomi', 'Charis', 'ckegley9w@mlb.com', 'uSFJ6n', '2008-12-26', 'true', 'F', '1562 Moose Alley', '1983-04-26');
INSERT INTO PetOwner VALUES ('Crystie', 'Carolin', 'chovard9x@blogtalkradio.com', 'TqZ2nApZ', '2012-12-10', 'true', 'F', '28512 Lyons Drive', '1935-08-30');
INSERT INTO PetOwner VALUES ('Dulsea', 'Mitzi', 'mgabbitas9y@ucoz.ru', 'rC9vhMiN', '2009-11-25', 'true', 'F', '9 Kropf Pass', '1994-10-01');
INSERT INTO PetOwner VALUES ('Arlin', 'Hasheem', 'hlyptratt9z@sbwire.com', 'UuvikucQ', '2019-07-08', 'true', 'M', '16 Gale Center', '1941-08-02');
INSERT INTO PetOwner VALUES ('Hiram', 'Barnaby', 'bklassmana0@people.com.cn', 'jHSAAYm', '2019-09-16', 'true', 'M', '07665 Rutledge Hill', '1959-07-18');
INSERT INTO PetOwner VALUES ('Stafford', 'Mahmoud', 'mstoakesa1@w3.org', 'LgOeYp', '2010-04-29', 'true', 'M', '5 High Crossing Circle', '2004-09-02');
INSERT INTO PetOwner VALUES ('Richard', 'Egon', 'eubanksa2@squarespace.com', 'vYujwQMQqxaN', '2011-01-08', 'true', 'M', '1 Fremont Street', '1978-08-29');
INSERT INTO PetOwner VALUES ('Cele', 'Rene', 'ritzkovitcha4@dailymotion.com', 'ho6uyu', '2002-05-05', 'true', 'F', '38901 Hansons Plaza', '1974-10-10');
INSERT INTO PetOwner VALUES ('Welbie', 'Elston', 'epettersa5@gizmodo.com', 'ihwLpMChtE', '2009-08-09', 'true', 'M', '9 Birchwood Crossing', '2004-08-09');
INSERT INTO PetOwner VALUES ('Albertine', 'Cassey', 'cpengelleya6@youku.com', 'i8C8vWYMH', '2002-09-21', 'true', 'F', '48887 American Ash Way', '1966-08-26');
INSERT INTO PetOwner VALUES ('Amata', 'Erina', 'ecaustona7@google.com.au', 'aUDWE5', '2016-11-14', 'true', 'F', '20 La Follette Hill', '1987-08-01');
INSERT INTO PetOwner VALUES ('Cher', 'Adelice', 'afaugheya8@yelp.com', '8xHlVV88Bi', '2008-06-03', 'true', 'F', '19847 Farragut Lane', '1961-05-18');
INSERT INTO PetOwner VALUES ('Arturo', 'Avram', 'abrislanab@domainmarket.com', 'O7Fy5OSdz', '2011-06-15', 'true', 'M', '3 Dorton Place', '2017-11-07');
INSERT INTO PetOwner VALUES ('Chick', 'Herschel', 'hgligoraciac@gov.uk', 'DpZVHO', '2014-05-28', 'false', 'M', '2 Goodland Drive', '1973-05-11');
INSERT INTO PetOwner VALUES ('Germana', 'Lorraine', 'lbenkoad@hatena.ne.jp', 'wmeZeQLX', '2009-11-25', 'true', 'F', '942 Barby Point', '1960-07-17');
INSERT INTO PetOwner VALUES ('Hillyer', 'Vinnie', 'vmacgillicuddyae@cargocollective.com', 'WiG9z5XRaIDC', '2017-06-04', 'true', 'M', '3151 Nelson Park', '2001-08-04');
INSERT INTO PetOwner VALUES ('Galvan', 'Shelby', 'splemingaf@vk.com', 'rpDrEcDun', '2005-06-29', 'false', 'M', '8 Rutledge Junction', '2006-05-14');
INSERT INTO PetOwner VALUES ('Rayna', 'Ermina', 'ekettlesag@ebay.com', 'rg1WwD3', '2015-11-20', 'false', 'F', '456 Milwaukee Drive', '1949-12-23');
INSERT INTO PetOwner VALUES ('Manuel', 'Pepillo', 'ppardieah@odnoklassniki.ru', 'E8yQapzKX9x', '2014-10-04', 'false', 'M', '51372 Homewood Hill', '1976-08-02');
INSERT INTO PetOwner VALUES ('Saxon', 'Avery', 'aeadenai@ocn.ne.jp', 's3G54fL4', '2015-04-02', 'true', 'M', '0 Sutherland Drive', '1983-06-06');
INSERT INTO PetOwner VALUES ('Lettie', 'Ardath', 'aloadaj@theguardian.com', 'Nogplkg', '2009-10-26', 'true', 'F', '05 Katie Lane', '1955-09-24');
INSERT INTO PetOwner VALUES ('Eamon', 'Kermie', 'kcatterillak@wordpress.org', 'dvRdNnoE', '2012-03-06', 'false', 'M', '517 Arapahoe Terrace', '2007-01-13');
INSERT INTO PetOwner VALUES ('Hillard', 'Rafaello', 'rscollandal@163.com', 'CwEfZ0aH', '2001-01-10', 'false', 'M', '5 Westerfield Court', '2006-10-22');
INSERT INTO PetOwner VALUES ('Marlene', 'Miranda', 'mjentam@apple.com', 'VZLwKnXH', '2012-02-29', 'true', 'F', '820 Russell Park', '1996-07-06');
INSERT INTO PetOwner VALUES ('Jason', 'Mickey', 'mlittlepagean@phoca.cz', 'Fex4hStlAbZ', '2002-06-26', 'false', 'M', '6 Nova Point', '2015-02-22');
INSERT INTO PetOwner VALUES ('Anabelle', 'Kori', 'kphillipsonao@tamu.edu', 'TAKVfb', '2011-06-21', 'true', 'F', '47277 Utah Court', '2019-05-19');
INSERT INTO PetOwner VALUES ('Brit', 'Monti', 'mthomelinap@microsoft.com', 'XaUnpO1NsqCb', '2002-12-19', 'false', 'M', '6 West Center', '2002-09-23');
INSERT INTO PetOwner VALUES ('Florian', 'Kelly', 'khatfieldaq@goodreads.com', '2giv1loq4l8Z', '2003-12-15', 'false', 'M', '73368 Green Lane', '1973-12-05');
INSERT INTO PetOwner VALUES ('Mal', 'Bennie', 'bstentar@ucoz.com', 'vZHjmKHD', '2005-04-25', 'true', 'M', '6 Caliangt Way', '1964-05-08');
INSERT INTO PetOwner VALUES ('Rudolph', 'Jeremiah', 'jenriquesas@ycombinator.com', 'tSzUnxBpO2bT', '2010-07-31', 'false', 'M', '61 Hoepker Hill', '1992-05-15');
INSERT INTO PetOwner VALUES ('Melisa', 'Jessica', 'jshackelat@macromedia.com', 'boJUz5', '2011-01-20', 'true', 'F', '08687 Kropf Point', '1984-04-03');
INSERT INTO PetOwner VALUES ('Heall', 'Westbrook', 'whowtopreserveau@macromedia.com', 'EK2F1WGn', '2017-04-09', 'false', 'M', '38664 Vernon Drive', '1979-11-06');
INSERT INTO PetOwner VALUES ('Wiley', 'Isadore', 'istickellsav@wiley.com', 'CseR2Dklow', '2010-07-04', 'false', 'M', '16 Monica Avenue', '1989-05-05');
INSERT INTO PetOwner VALUES ('Fernande', 'Stella', 'sscoffinsaw@tinypic.com', 'Uhmm71', '2020-01-11', 'true', 'F', '97 Eastwood Parkway', '2015-12-26');
INSERT INTO PetOwner VALUES ('Berty', 'Xenos', 'xholleranax@issuu.com', 'uXprH4xsm', '2010-07-19', 'true', 'M', '53844 Cherokee Alley', '1982-01-03');
INSERT INTO PetOwner VALUES ('Yule', 'Connor', 'crowcliffeay@house.gov', 'v93Ba5qg', '2009-07-04', 'true', 'M', '2423 Fairview Road', '2011-03-08');
INSERT INTO PetOwner VALUES ('Dukie', 'Maximilian', 'mdeattaaz@pen.io', 'kTQyqfP1XIYI', '2008-05-21', 'true', 'M', '3 Dennis Parkway', '1966-11-06');
INSERT INTO PetOwner VALUES ('Karlens', 'Fair', 'fjedrykab0@yandex.ru', 'wceHFDfTYc', '2010-03-24', 'false', 'M', '8502 Truax Center', '1991-09-10');
INSERT INTO PetOwner VALUES ('Elle', 'Rebe', 'rmallindineb1@tinyurl.com', 'HyeedbePM', '2012-05-15', 'true', 'F', '1135 David Crossing', '2007-11-17');
INSERT INTO PetOwner VALUES ('Vaughan', 'Alleyn', 'aaggottb2@pinterest.com', '3PvmQwMAGX77', '2016-06-24', 'false', 'M', '96 Fair Oaks Hill', '1937-08-25');
INSERT INTO PetOwner VALUES ('Basile', 'Darn', 'dmeadwayb3@themeforest.net', 'tOPRzxLTWZJ', '2015-12-05', 'false', 'M', '49 Lakewood Place', '2020-07-11');
INSERT INTO PetOwner VALUES ('Tonya', 'Shina', 'sbilbrookb4@linkedin.com', 'Pt721MJKwM', '2003-01-30', 'false', 'F', '994 Prentice Way', '2016-07-23');
INSERT INTO PetOwner VALUES ('Nichols', 'Wheeler', 'wcolleranb5@shop-pro.jp', 'nQdWeo0KBrO', '2017-08-26', 'false', 'M', '0534 Holy Cross Lane', '1935-06-07');
INSERT INTO PetOwner VALUES ('Brody', 'Henrik', 'hsiggensb6@rakuten.co.jp', 'pTRhRJDU31S', '2020-02-19', 'true', 'M', '42 Esch Parkway', '1962-09-11');
INSERT INTO PetOwner VALUES ('Philis', 'Jen', 'jbennionb7@google.com.br', '3BRM4lcr', '2012-08-22', 'true', 'F', '3 Maple Road', '2017-05-13');
INSERT INTO PetOwner VALUES ('Bertie', 'Sutton', 'swingerb8@apache.org', 'vhW3OFwn5Peu', '2007-10-25', 'false', 'M', '5524 Katie Crossing', '1959-09-16');
INSERT INTO PetOwner VALUES ('Issi', 'Adiana', 'adufaurb9@theatlantic.com', 'qFsw54yY618', '2006-08-31', 'false', 'F', '4377 Westport Parkway', '2018-07-29');
INSERT INTO PetOwner VALUES ('Florentia', 'Aleece', 'abriersba@fastcompany.com', 'jbSp1v', '2009-05-13', 'true', 'F', '1214 Fremont Point', '1956-09-27');
INSERT INTO PetOwner VALUES ('Ludovika', 'L;urette', 'lbrunsdonbb@sina.com.cn', 'akj9awbdKJ', '2013-04-28', 'false', 'F', '34 Superior Point', '2008-08-24');
INSERT INTO PetOwner VALUES ('Collen', 'Lillian', 'lwaterworthbc@va.gov', 'Ld2SzcyvXA3y', '2009-06-19', 'true', 'F', '5 Everett Avenue', '1950-05-17');
INSERT INTO PetOwner VALUES ('Worden', 'Lonny', 'lbrimmacombebd@baidu.com', 'WXqGNX6ykH', '2015-11-27', 'false', 'M', '9139 Bultman Terrace', '1964-08-28');
INSERT INTO PetOwner VALUES ('Louella', 'Estell', 'ecranfieldbe@slashdot.org', 'O5pAN6rw', '2012-07-15', 'true', 'F', '64739 Mendota Circle', '2018-07-20');
INSERT INTO PetOwner VALUES ('Gregorius', 'Demott', 'dpaigebf@trellian.com', '81zwKk', '2011-06-26', 'false', 'M', '6 Vera Street', '1957-01-01');
INSERT INTO PetOwner VALUES ('Wesley', 'Frazier', 'fscusebg@shareasale.com', 'zIQDFSAss', '2019-10-06', 'true', 'M', '0 Schlimgen Road', '1940-02-17');
INSERT INTO PetOwner VALUES ('Merill', 'Zollie', 'zpinckstonebh@google.co.uk', 'MYhudxcnguw', '2008-04-04', 'true', 'M', '3 Hazelcrest Lane', '1933-07-18');
INSERT INTO PetOwner VALUES ('Dynah', 'Brita', 'bflemyngbi@wsj.com', 'mtwHKbuzB0d9', '2015-10-24', 'true', 'F', '694 Menomonie Junction', '1963-02-07');
INSERT INTO PetOwner VALUES ('Shari', 'Glyn', 'gtewkesburybj@unesco.org', 'GdN9uZpZ', '2004-01-20', 'false', 'F', '39973 Hauk Terrace', '1969-08-10');
INSERT INTO PetOwner VALUES ('Lamont', 'Osmund', 'oconnochiebk@tinypic.com', 'rcp2xg9', '2011-09-02', 'true', 'M', '85235 Steensland Avenue', '1958-09-19');
INSERT INTO PetOwner VALUES ('Hildagard', 'Eleanore', 'emaevelabl@washingtonpost.com', '3kDEllHL', '2014-02-14', 'false', 'F', '2 Trailsway Plaza', '1950-10-25');
INSERT INTO PetOwner VALUES ('Arline', 'Jeannette', 'jclaremontbm@technorati.com', 'eKL0FnYN1x9Z', '2018-05-25', 'true', 'F', '6 Shopko Crossing', '1941-09-10');
INSERT INTO PetOwner VALUES ('Malinde', 'Anni', 'amcinallybn@auda.org.au', 'ufH6cHmW1', '2001-05-30', 'true', 'F', '198 Boyd Hill', '1946-04-02');
INSERT INTO PetOwner VALUES ('Bob', 'Burke', 'bfrybo@miibeian.gov.cn', 'kZu1jI9wNa7E', '2003-11-08', 'false', 'M', '15 Namekagon Circle', '1945-03-01');
INSERT INTO PetOwner VALUES ('Hedvig', 'Dyane', 'dmilnerbp@webeden.co.uk', '0TaMiaUycy0', '2004-04-23', 'false', 'F', '82 Warner Plaza', '1954-05-23');
INSERT INTO PetOwner VALUES ('Babbette', 'Camellia', 'cventonbq@uol.com.br', 'Ym4OOYv5NtZ', '2008-03-11', 'true', 'F', '8 Thierer Parkway', '1972-01-05');
INSERT INTO PetOwner VALUES ('Giacopo', 'Sayres', 'svuittonbr@spiegel.de', 'bUgTOFUMhC', '2015-02-12', 'false', 'M', '16 Victoria Trail', '2006-10-21');
INSERT INTO PetOwner VALUES ('Brett', 'Elfreda', 'emaffybs@tuttocitta.it', 'ectJRt', '2009-06-04', 'false', 'F', '220 Sloan Center', '2011-06-16');
INSERT INTO PetOwner VALUES ('Jonah', 'Radcliffe', 'rtooheybt@microsoft.com', 'a1r2RFo6dUZ', '2012-02-12', 'true', 'M', '521 Bellgrove Lane', '1955-04-26');
INSERT INTO PetOwner VALUES ('Theda', 'Isabel', 'ibruffellbu@wordpress.org', '51DWZ5L', '2018-06-09', 'false', 'F', '00009 Ridgeview Court', '1970-02-22');
INSERT INTO PetOwner VALUES ('Evita', 'Wenda', 'wbeddiebv@va.gov', 'anIZ29mIgb', '2010-04-19', 'true', 'F', '19707 Eliot Plaza', '1957-11-18');
INSERT INTO PetOwner VALUES ('Erinn', 'Dawna', 'dmulqueenbw@freewebs.com', 'K7TwvHDKpaw', '2020-10-07', 'true', 'F', '5 Luster Crossing', '2001-05-04');
INSERT INTO PetOwner VALUES ('Emmi', 'Imogene', 'imitchensonbx@devhub.com', '9tmgxfRlTY', '2009-05-29', 'true', 'F', '28469 Pierstorff Court', '1987-09-24');
INSERT INTO PetOwner VALUES ('Gloriane', 'Gigi', 'gliddelby@sciencedaily.com', 'nQy9gZO7za', '2006-08-27', 'false', 'F', '0406 Chinook Court', '1932-08-16');
INSERT INTO PetOwner VALUES ('Burton', 'Ahmed', 'acockshottbz@mashable.com', 'Bpw08R', '2007-08-25', 'true', 'M', '1 Rieder Circle', '2005-11-12');
INSERT INTO PetOwner VALUES ('Mendel', 'Giorgi', 'gblizardc0@aol.com', 'JeozkIHmM', '2008-01-09', 'true', 'M', '75 Gateway Crossing', '1935-11-13');
INSERT INTO PetOwner VALUES ('Horace', 'Bevan', 'brewcassellc1@hhs.gov', 'rzxXB9', '2009-10-07', 'true', 'M', '28296 Springview Pass', '2013-12-13');
INSERT INTO PetOwner VALUES ('Kyla', 'Coreen', 'cmcgarrahanc2@amazon.de', 'yjjqbg', '2016-11-06', 'true', 'F', '869 Arapahoe Lane', '1932-12-22');
INSERT INTO PetOwner VALUES ('Winna', 'Lurette', 'lhacunc3@mashable.com', 'smR6K35BqP', '2009-10-22', 'false', 'F', '042 Rockefeller Way', '2020-04-27');
INSERT INTO PetOwner VALUES ('Zebulen', 'Felike', 'ftithacottc4@g.co', 'qol9c36NB', '2013-01-27', 'true', 'M', '6835 Trailsway Lane', '1997-05-13');
INSERT INTO PetOwner VALUES ('Durand', 'Corby', 'cbotemanc5@gov.uk', 'jetyu8Wnbjsy', '2015-10-12', 'true', 'M', '62 Delladonna Junction', '2015-06-15');
INSERT INTO PetOwner VALUES ('Malia', 'Daffie', 'dsnoxellc6@gnu.org', 'jcuURogv1w5', '2020-03-31', 'true', 'F', '13808 Erie Circle', '1950-09-07');
INSERT INTO PetOwner VALUES ('Osmond', 'Porty', 'ppoleyc7@shutterfly.com', 'WhQbT6sf', '2015-08-02', 'false', 'M', '75522 Melby Court', '1959-08-31');
INSERT INTO PetOwner VALUES ('Falito', 'Sam', 'sboughc8@army.mil', 'XmAHSYZfI', '2010-03-24', 'true', 'M', '69 Stuart Pass', '1978-09-11');
INSERT INTO PetOwner VALUES ('Lorelle', 'Frieda', 'fkasselc9@prweb.com', 'ZvstyXR', '2004-01-17', 'true', 'F', '859 Schiller Hill', '1989-03-21');
INSERT INTO PetOwner VALUES ('Grady', 'Tammy', 'tsailsca@chicagotribune.com', '0P085Su', '2010-07-18', 'true', 'M', '21 Brentwood Trail', '1998-03-29');
INSERT INTO PetOwner VALUES ('Trudie', 'Kayley', 'kdancercb@theglobeandmail.com', 'FEcPM8KO6', '2008-04-15', 'false', 'F', '661 Thackeray Court', '2006-12-02');
INSERT INTO PetOwner VALUES ('Trish', 'Beatrisa', 'bconstantinoucc@whitehouse.gov', 'gGNgfG', '2008-05-22', 'false', 'F', '699 Sullivan Hill', '1983-03-25');
INSERT INTO PetOwner VALUES ('Delly', 'Louisa', 'lcrutchleycd@alexa.com', 'wMMup6d2', '2011-11-04', 'false', 'F', '899 Little Fleur Crossing', '1949-08-24');
INSERT INTO PetOwner VALUES ('Barney', 'Isa', 'idoncomce@blogtalkradio.com', 'JeDemJW', '2001-04-04', 'false', 'M', '177 Schiller Pass', '1945-07-22');
INSERT INTO PetOwner VALUES ('Val', 'Jo ann', 'jminchindencf@jimdo.com', 'zzUruzcFVBbH', '2015-06-27', 'false', 'F', '364 Fisk Drive', '1983-04-26');
INSERT INTO PetOwner VALUES ('Anallise', 'Tonya', 'tpimlettcg@fotki.com', 'V5JadvN', '2008-07-03', 'true', 'F', '1 Bultman Point', '2013-01-14');
INSERT INTO PetOwner VALUES ('Marshall', 'Ingamar', 'iheinekech@vistaprint.com', '8MTJf7Ey', '2009-12-27', 'false', 'M', '954 Marquette Trail', '1956-01-29');
INSERT INTO PetOwner VALUES ('Myrilla', 'Holly-anne', 'hblaseci@princeton.edu', 'qgODfo8', '2011-08-15', 'false', 'F', '17485 Mosinee Plaza', '2004-08-10');
INSERT INTO PetOwner VALUES ('Leonora', 'Elvera', 'eyakobcj@imgur.com', 'FDS7fImrzPs', '2007-06-03', 'true', 'F', '84039 Scott Crossing', '2005-02-03');
INSERT INTO PetOwner VALUES ('Dannel', 'Codi', 'cmacvaghck@epa.gov', 'Gn9HLeBzU8', '2011-06-16', 'true', 'M', '8 Bluejay Lane', '1982-02-08');
INSERT INTO PetOwner VALUES ('Carolyn', 'Addy', 'achelnamcl@ucoz.com', 'ouCUAHpWTnjW', '2010-11-24', 'true', 'F', '4 Wayridge Place', '2009-01-10');
INSERT INTO PetOwner VALUES ('Samuele', 'Joshia', 'jdymottcm@xinhuanet.com', 'inlmdqbXtf', '2000-12-01', 'true', 'M', '2 Gulseth Court', '1943-03-29');
INSERT INTO PetOwner VALUES ('Oswell', 'Uri', 'ucolmercn@ihg.com', '7jIDiPdjSy', '2019-12-07', 'false', 'M', '44 Fallview Parkway', '1965-11-27');
INSERT INTO PetOwner VALUES ('Amalita', 'Ede', 'espridgeonco@nationalgeographic.com', 'hB3dUarsOc', '2016-08-07', 'true', 'F', '8 Pine View Park', '1941-06-21');
INSERT INTO PetOwner VALUES ('Culley', 'Trefor', 'troydscp@msu.edu', 'vVdOysTUoCCj', '2016-07-04', 'true', 'M', '5 Moose Circle', '1978-04-01');
INSERT INTO PetOwner VALUES ('Nikolas', 'Chick', 'cbranfordcq@sakura.ne.jp', 'hnGofDrfo', '2009-06-17', 'true', 'M', '57777 Dottie Terrace', '1969-09-11');
INSERT INTO PetOwner VALUES ('Ritchie', 'Jayme', 'jsachcr@fema.gov', 'U9m5lF4Lz', '2006-04-12', 'false', 'M', '91183 Ridgeway Lane', '2016-05-31');
INSERT INTO PetOwner VALUES ('Donielle', 'Lucila', 'lhammanct@flavors.me', 'I8rxgbz', '2003-01-19', 'true', 'F', '8264 Pleasure Trail', '1991-05-08');
INSERT INTO PetOwner VALUES ('Maxi', 'Shandra', 'stheodorecu@nbcnews.com', 'ly5bOwv', '2011-02-19', 'false', 'F', '48 Columbus Court', '2017-06-19');
INSERT INTO PetOwner VALUES ('Doralynne', 'Lotta', 'lgladbeckcv@indiatimes.com', 'jFWQnHcPUz', '2008-08-29', 'true', 'F', '7946 Truax Lane', '1974-04-11');
INSERT INTO PetOwner VALUES ('Daren', 'Claybourne', 'cbartoszewiczcx@comsenz.com', 'p5IIXURb', '2008-02-24', 'true', 'M', '70 Pond Park', '2002-01-08');
INSERT INTO PetOwner VALUES ('Giffie', 'Arturo', 'avasquezcy@dell.com', '6IStEMEsb', '2016-01-22', 'true', 'M', '346 Thackeray Pass', '1966-07-16');
INSERT INTO PetOwner VALUES ('Rozelle', 'Julee', 'jjachimakcz@amazon.co.uk', 'et5xPgqyxy', '2012-08-05', 'false', 'F', '6150 Darwin Pass', '1973-02-27');
INSERT INTO PetOwner VALUES ('Pascal', 'Bernie', 'bharbertsond0@wordpress.org', 'cafooHcaVpb8', '2006-10-07', 'true', 'M', '74710 Southridge Court', '1967-09-21');
INSERT INTO PetOwner VALUES ('Heinrick', 'Cameron', 'cabbisd1@usda.gov', 'tMZtx8Vu', '2001-05-09', 'false', 'M', '8429 Petterle Drive', '1967-01-08');
INSERT INTO PetOwner VALUES ('Teodoor', 'Horatio', 'hfallensd2@seesaa.net', '9bAk5Zzu', '2011-09-21', 'true', 'M', '516 Roxbury Way', '1952-10-08');
INSERT INTO PetOwner VALUES ('Sasha', 'Ruddie', 'rdaniaudd3@miibeian.gov.cn', 'OkJpVyi5YI', '2007-07-15', 'true', 'M', '6675 Ridgeview Street', '1997-11-17');
INSERT INTO PetOwner VALUES ('Clive', 'Jesse', 'jfarressd4@rediff.com', 'GRIX0K0QIs', '2009-04-26', 'false', 'M', '882 Talisman Drive', '2002-12-01');
INSERT INTO PetOwner VALUES ('Morten', 'Emmett', 'elebarrd5@1688.com', 'EwAmgZE', '2007-01-06', 'true', 'M', '5953 Basil Avenue', '2005-06-17');
INSERT INTO PetOwner VALUES ('Agna', 'Jonie', 'jmckendryd6@domainmarket.com', 'Rgwu1eEfD3V8', '2014-02-01', 'true', 'F', '3 Luster Circle', '1933-04-21');
INSERT INTO PetOwner VALUES ('Torr', 'Dylan', 'dbiasiolid7@slideshare.net', '1l5OnmgP', '2017-01-12', 'true', 'M', '7285 Arizona Pass', '1987-09-25');
INSERT INTO PetOwner VALUES ('Liesa', 'Hally', 'hlannond8@sbwire.com', 'BbVzwRhLD', '2006-06-04', 'true', 'F', '38 Victoria Street', '1940-10-25');
INSERT INTO PetOwner VALUES ('Lammond', 'Anatollo', 'aahrendsend9@netscape.com', 'HKSUlfrDks', '2005-12-26', 'false', 'M', '6350 Garrison Junction', '1940-12-20');
INSERT INTO PetOwner VALUES ('Laney', 'Marten', 'myeamanda@vistaprint.com', 'IoKrLDU', '2005-03-24', 'true', 'M', '122 Chive Court', '1956-12-08');
INSERT INTO PetOwner VALUES ('Karoly', 'Ray', 'rsmyliedb@list-manage.com', 'nnB4fx6h', '2016-11-23', 'false', 'M', '103 Lyons Place', '1936-03-20');
INSERT INTO PetOwner VALUES ('Yank', 'Rey', 'rgirkindc@ask.com', 'Tf4JgGv6ioUb', '2010-11-07', 'false', 'M', '0807 Vidon Junction', '1955-08-10');
INSERT INTO PetOwner VALUES ('Willdon', 'Noach', 'ndenmeaddd@reference.com', 'e71ymA1ZF5', '2004-09-04', 'true', 'M', '709 Mccormick Lane', '1987-04-30');
INSERT INTO PetOwner VALUES ('Dewitt', 'Anderson', 'agifkinsde@gmpg.org', 'SdxTbtIr', '2020-07-28', 'false', 'M', '589 Weeping Birch Pass', '1971-03-04');
INSERT INTO PetOwner VALUES ('Beryle', 'Adelind', 'amethuendf@devhub.com', 'PphmYlH5r', '2001-04-18', 'true', 'F', '602 Schiller Road', '1930-12-30');
INSERT INTO PetOwner VALUES ('Dorian', 'Winn', 'wmorelanddg@imgur.com', 'woeAMA148', '2003-03-24', 'true', 'M', '4 Judy Point', '1944-12-23');
INSERT INTO PetOwner VALUES ('Lowell', 'Clarence', 'cspringalldh@dmoz.org', 'E1SFTgqM2Mx', '2008-03-05', 'true', 'M', '65991 Comanche Alley', '1951-05-19');
INSERT INTO PetOwner VALUES ('Ezequiel', 'Clim', 'ccottelldi@rediff.com', 'L1JJTW1KFgr', '2015-06-23', 'true', 'M', '60076 Barby Avenue', '1932-03-31');
INSERT INTO PetOwner VALUES ('Nick', 'Hastie', 'hcarusdj@ibm.com', 'rqUahU', '2004-12-26', 'false', 'M', '84985 Sunfield Alley', '1942-05-11');
INSERT INTO PetOwner VALUES ('Armando', 'Jedd', 'jstockowdk@hp.com', 'BRwkKx7PD4', '2007-03-28', 'true', 'M', '9020 Scofield Lane', '1952-02-14');
INSERT INTO PetOwner VALUES ('Carry', 'Kissee', 'kheggedl@goo.gl', '9aZxf7PXEti', '2004-01-26', 'true', 'F', '2230 Old Shore Drive', '1939-03-23');
INSERT INTO PetOwner VALUES ('Antons', 'Kayne', 'kcawstondm@kickstarter.com', 'peWJUH2p04b', '2015-08-30', 'true', 'M', '7 Lotheville Alley', '2014-04-06');
INSERT INTO PetOwner VALUES ('Dorisa', 'Beverlie', 'bbrambelldn@oakley.com', 'V6WW69x4p', '2014-02-17', 'true', 'F', '0080 Dakota Park', '1992-10-29');
INSERT INTO PetOwner VALUES ('Redd', 'Devlen', 'dfriedmando@smugmug.com', 'Mvub24qk', '2016-08-17', 'false', 'M', '819 Fremont Way', '2016-07-13');
INSERT INTO PetOwner VALUES ('Rouvin', 'Filmer', 'fbertranddp@google.cn', 'PTncxTny', '2014-06-11', 'false', 'M', '7095 Fairview Pass', '2006-10-12');
INSERT INTO PetOwner VALUES ('Wynny', 'Ulrica', 'uclemmensendq@friendfeed.com', 'EXznBNNa9A', '2002-06-09', 'false', 'F', '8 Stang Alley', '1967-08-15');
INSERT INTO PetOwner VALUES ('Elka', 'Flossy', 'fludyedr@businessweek.com', 'z8H4PQWzv', '2014-07-30', 'false', 'F', '42331 Onsgard Avenue', '1952-12-22');
INSERT INTO PetOwner VALUES ('Beatriz', 'Kerrie', 'kwelchds@youtu.be', 'VNpGFejz', '2019-03-22', 'false', 'F', '813 Johnson Trail', '1971-04-29');
INSERT INTO PetOwner VALUES ('Othelia', 'Noell', 'npavlishchevdt@google.cn', 'dqVgSMlOvZ', '2002-02-01', 'false', 'F', '46 Dawn Hill', '1945-09-14');
INSERT INTO PetOwner VALUES ('Sheila', 'Maribelle', 'mnabarrodu@exblog.jp', 'BQx2arSLvfB', '2009-03-10', 'true', 'F', '5 Reindahl Drive', '1981-01-11');
INSERT INTO PetOwner VALUES ('Misti', 'Vi', 'vfarryandv@cpanel.net', 'jXjV6LZ', '2014-08-06', 'false', 'F', '362 Farmco Court', '2010-07-11');
INSERT INTO PetOwner VALUES ('Darryl', 'Aubert', 'agyurkovicsdw@dion.ne.jp', 'UfUtofONWJ', '2010-02-23', 'true', 'M', '4 Fieldstone Hill', '1958-04-01');
INSERT INTO PetOwner VALUES ('Lyda', 'Shoshana', 'sterreydx@indiegogo.com', 'RAagD407ayeH', '2015-08-11', 'true', 'F', '52312 Lyons Alley', '1931-08-02');
INSERT INTO PetOwner VALUES ('Doralin', 'Vyky', 'vjefferiesdy@google.fr', 'LJEXbxR2', '2002-03-05', 'true', 'F', '87816 Cardinal Drive', '2016-06-22');
INSERT INTO PetOwner VALUES ('Cristiano', 'Chevy', 'cmilmodz@usatoday.com', '6vAELnVOFw', '2002-02-06', 'true', 'M', '8 Sheridan Alley', '2001-08-11');
INSERT INTO PetOwner VALUES ('Aggy', 'Dulsea', 'dholte0@creativecommons.org', 'WsFJa7E65ZNh', '2001-03-30', 'true', 'F', '730 Village Lane', '1974-07-29');
INSERT INTO PetOwner VALUES ('Iseabal', 'Teddi', 'tgerardote1@wikia.com', 'OxlfI9yHJ', '2016-12-10', 'false', 'F', '002 Goodland Way', '1969-09-16');
INSERT INTO PetOwner VALUES ('Alejandrina', 'Lorry', 'lhelmkee2@ocn.ne.jp', '7XYgwILR', '2005-11-01', 'true', 'F', '4993 Coleman Hill', '2017-10-26');
INSERT INTO PetOwner VALUES ('Alfred', 'Costa', 'charralde3@themeforest.net', 'bLI7IUST9', '2015-08-31', 'false', 'M', '0173 7th Drive', '1972-08-28');
INSERT INTO PetOwner VALUES ('Sheela', 'Chrysler', 'chullere4@europa.eu', 'jovNLdIq', '2004-08-31', 'true', 'F', '43177 Larry Drive', '1970-04-10');
INSERT INTO PetOwner VALUES ('Andie', 'Fred', 'fheddone5@nifty.com', 'rQbTNW8mt', '2006-09-22', 'true', 'F', '9713 Division Avenue', '1990-05-02');
INSERT INTO PetOwner VALUES ('Humfrid', 'Scarface', 'sstimsone6@marketwatch.com', 'v0IMkrp', '2008-05-04', 'false', 'M', '2 Sachtjen Court', '1960-12-08');
INSERT INTO PetOwner VALUES ('Humbert', 'Marchall', 'mliversagee7@phoca.cz', '0jgSFPc0gN', '2015-05-06', 'true', 'M', '66 Lakewood Lane', '1995-11-10');
INSERT INTO PetOwner VALUES ('Vail', 'Pavlov', 'paharonie9@lycos.com', 'LJYpLo', '2017-03-01', 'true', 'M', '2778 6th Trail', '1993-11-13');
INSERT INTO PetOwner VALUES ('Patton', 'Tannie', 'tbeartupea@foxnews.com', 'eG2pDPMpC', '2012-11-06', 'true', 'M', '38 Redwing Alley', '1957-07-13');
INSERT INTO PetOwner VALUES ('Alanna', 'Breena', 'bocorreb@w3.org', '6eqW4vg', '2002-12-01', 'false', 'F', '1 Cardinal Crossing', '1953-01-03');
INSERT INTO PetOwner VALUES ('Bobette', 'Nonah', 'nyeomanec@ibm.com', 'NMwJ6w', '2004-05-11', 'false', 'F', '0 Paget Park', '1978-08-29');
INSERT INTO PetOwner VALUES ('Constancia', 'Del', 'dscaplehorned@google.co.uk', 'Ha9gp1Vudd', '2003-06-18', 'false', 'F', '90859 Mayer Crossing', '2020-03-02');
INSERT INTO PetOwner VALUES ('Ellsworth', 'Erhart', 'edehooghee@marriott.com', 'LUiZTtg53bP', '2002-01-19', 'true', 'M', '7350 Independence Drive', '2019-01-29');
INSERT INTO PetOwner VALUES ('Waldon', 'Carleton', 'cstortonef@alexa.com', 'f3KV9ddf', '2018-07-05', 'true', 'M', '6838 Dakota Hill', '1962-11-18');
INSERT INTO PetOwner VALUES ('Enrique', 'Wyndham', 'wclintoneg@wisc.edu', 'Gu2P06', '2018-03-10', 'false', 'M', '57823 Sunnyside Trail', '1936-03-17');
INSERT INTO PetOwner VALUES ('Virgie', 'Raimundo', 'rparadineeh@xrea.com', '50CJ5Y', '2011-03-10', 'true', 'M', '6 Larry Street', '2002-10-10');
INSERT INTO PetOwner VALUES ('Henrik', 'Mano', 'mdurlingei@sciencedaily.com', 'EjY86nVdNd', '2006-06-24', 'false', 'M', '8957 1st Point', '1989-07-01');
INSERT INTO PetOwner VALUES ('Celia', 'Abbie', 'ariochej@senate.gov', 'MErwpSDZU', '2009-01-27', 'true', 'F', '1706 Nelson Court', '1996-02-07');
INSERT INTO PetOwner VALUES ('Reinaldos', 'Anderson', 'abushellek@noaa.gov', 'bJ5aWpuKWtc', '2013-05-14', 'false', 'M', '04659 Welch Drive', '2016-08-25');
INSERT INTO PetOwner VALUES ('Hamlen', 'Ruprecht', 'rfroomeel@youku.com', 'NJAzC87n', '2012-05-02', 'true', 'M', '2 Badeau Parkway', '1967-09-27');
INSERT INTO PetOwner VALUES ('Rosco', 'Lowe', 'lcowperthwaiteem@canalblog.com', '3IKfAph36TGt', '2016-07-04', 'true', 'M', '20 Arapahoe Terrace', '1934-11-20');
INSERT INTO PetOwner VALUES ('Sonni', 'Kiersten', 'kstledgeren@is.gd', 'F0mWNPpp6', '2007-07-18', 'true', 'F', '3308 Kinsman Terrace', '1933-12-21');
INSERT INTO PetOwner VALUES ('Patrizius', 'Burton', 'boraneo@nationalgeographic.com', '0AP4c8Bf', '2020-06-01', 'true', 'M', '61871 Golden Leaf Place', '1992-09-25');
INSERT INTO PetOwner VALUES ('Prissie', 'Margie', 'mreisenep@networkadvertising.org', 'Of0OlvTEfuvK', '2007-04-01', 'true', 'F', '30 Porter Center', '1945-08-22');
INSERT INTO PetOwner VALUES ('Matthieu', 'Court', 'cmccathyeq@liveinternet.ru', 'NWuFS55MW', '2007-03-24', 'true', 'M', '25400 Longview Court', '1959-06-29');
INSERT INTO PetOwner VALUES ('Leonore', 'Lori', 'ldargaveler@engadget.com', '0fnWfKmyvtI8', '2006-05-21', 'false', 'F', '20678 Morning Plaza', '1959-06-09');
INSERT INTO PetOwner VALUES ('Cordell', 'Neddie', 'njannexes@cnn.com', 'S5PwfFZkA', '2015-06-29', 'true', 'M', '05 Waubesa Lane', '1974-11-26');
INSERT INTO PetOwner VALUES ('Pincas', 'Evan', 'elovartet@pagesperso-orange.fr', 'k1rttTC', '2006-12-22', 'false', 'M', '48710 Maple Wood Circle', '1988-01-20');
INSERT INTO PetOwner VALUES ('Wren', 'Liane', 'ljendaseu@mediafire.com', 'WbG5GbFyZcw', '2009-06-08', 'true', 'F', '45 Roth Circle', '1970-04-26');
INSERT INTO PetOwner VALUES ('Loreen', 'Lenna', 'lwiperew@cbslocal.com', '0XV8ZGGG42', '2016-09-11', 'false', 'F', '71 Old Shore Circle', '1953-07-08');
INSERT INTO PetOwner VALUES ('Frank', 'Abram', 'adraysayex@kickstarter.com', 'C8Z8A9OnX4L', '2002-09-26', 'false', 'M', '56112 Logan Trail', '1943-01-28');
INSERT INTO PetOwner VALUES ('Arv', 'Durand', 'djemmettey@ucoz.ru', 'VYtgJzmtR', '2005-06-27', 'true', 'M', '505 Kinsman Street', '1955-11-01');
INSERT INTO PetOwner VALUES ('Ynez', 'Sonny', 'smccuaigez@springer.com', 'OLBcKNlcG', '2010-04-29', 'false', 'F', '968 Carpenter Road', '1945-01-08');
INSERT INTO PetOwner VALUES ('Holmes', 'Beauregard', 'bblakemoref0@arstechnica.com', 'yW1XR2dfFusZ', '2005-03-18', 'false', 'M', '629 Hovde Place', '1978-09-05');
INSERT INTO PetOwner VALUES ('Jemima', 'Anetta', 'aoldmeadowf1@senate.gov', 'fZXTQAsQgcG7', '2008-07-31', 'true', 'F', '3298 Golf View Street', '2020-07-16');
INSERT INTO PetOwner VALUES ('Page', 'Kristoffer', 'ktosspellf2@51.la', 'G6hNgsH5', '2007-08-02', 'false', 'M', '8 Mccormick Crossing', '2005-08-08');
INSERT INTO PetOwner VALUES ('Edgard', 'Roman', 'rbleasf4@domainmarket.com', 'AzT28cUVsX6', '2014-10-21', 'false', 'M', '3 Del Mar Alley', '1990-12-09');
INSERT INTO PetOwner VALUES ('Brita', 'Adeline', 'ahercockf5@bigcartel.com', '3nr9wabFh17J', '2013-05-24', 'false', 'F', '17938 Schurz Street', '1957-11-08');
INSERT INTO PetOwner VALUES ('Arvie', 'Bard', 'bjerokf6@shinystat.com', 'WLPugoB0TIU7', '2020-07-09', 'false', 'M', '0829 Trailsway Center', '2008-06-12');
INSERT INTO PetOwner VALUES ('Alica', 'Fawnia', 'forsayf7@gmpg.org', 'RPJ8CXg1VT', '2018-03-17', 'true', 'F', '2183 Cherokee Road', '1938-06-26');
INSERT INTO PetOwner VALUES ('Bryon', 'Gaile', 'gswiresf8@miitbeian.gov.cn', 'C0RhsqZ', '2006-08-01', 'false', 'M', '81 Russell Place', '2001-11-20');
INSERT INTO PetOwner VALUES ('Hermina', 'Karyn', 'kdecazef9@photobucket.com', 'QT8l3s', '2014-05-09', 'false', 'F', '92 Annamark Lane', '1980-04-21');
INSERT INTO PetOwner VALUES ('Madalena', 'Sarita', 'srubinsaftfa@nba.com', 'GXOSKs8WhS3', '2003-02-02', 'true', 'F', '4 Kinsman Way', '2010-07-08');
INSERT INTO PetOwner VALUES ('Kurt', 'Alleyn', 'aiacovaccifb@reference.com', '5YkCI3KkRVQ', '2006-07-14', 'true', 'M', '54 Rowland Lane', '1944-11-05');
INSERT INTO PetOwner VALUES ('Misty', 'Adriena', 'aneemfc@washington.edu', 'VmLSlG', '2016-01-09', 'false', 'F', '46374 Fair Oaks Place', '1990-04-21');
INSERT INTO PetOwner VALUES ('Somerset', 'Hakeem', 'hkilmurryfd@rakuten.co.jp', 'Gdj0pqP', '2001-04-24', 'false', 'M', '5 Buhler Street', '1949-05-08');
INSERT INTO PetOwner VALUES ('Karlan', 'Abbott', 'abecomfe@utexas.edu', 'yGyecQ3EIHz', '2019-06-15', 'false', 'M', '0640 Superior Park', '1991-01-29');
INSERT INTO PetOwner VALUES ('Tammy', 'Dwight', 'dhylandff@accuweather.com', 'EWJWnsHYjP', '2010-10-04', 'true', 'M', '28662 Lyons Plaza', '1970-01-28');
INSERT INTO PetOwner VALUES ('Aeriela', 'Alexina', 'atitterellfg@nps.gov', 'uFzJ8M7j', '2011-10-07', 'true', 'F', '6 Jana Avenue', '1959-02-24');
INSERT INTO PetOwner VALUES ('Wendy', 'Starlene', 'srosariofh@joomla.org', 'EIpPu0EJkWK', '2004-12-25', 'true', 'F', '772 Sachtjen Court', '2015-08-06');
INSERT INTO PetOwner VALUES ('Celeste', 'Harriet', 'hwasmuthfi@zdnet.com', '4Pqgxlo5Z', '2012-10-11', 'true', 'F', '9 Truax Place', '1965-07-17');
INSERT INTO PetOwner VALUES ('Filbert', 'Justus', 'jmilsomfj@slate.com', 'tYdSI7N', '2007-06-25', 'false', 'M', '9 Claremont Plaza', '2010-11-06');
INSERT INTO PetOwner VALUES ('Cecil', 'Regan', 'rsleafordfk@hud.gov', 'a8tNaV', '2018-04-29', 'false', 'F', '929 Acker Place', '1947-04-08');
INSERT INTO PetOwner VALUES ('Emmanuel', 'Garfield', 'gduplantierfl@wsj.com', 'h5vFHe', '2019-11-11', 'true', 'M', '125 Barnett Circle', '1993-06-27');
INSERT INTO PetOwner VALUES ('Leigh', 'Clyve', 'cleemanfm@phpbb.com', 'IcCb2M', '2015-03-03', 'false', 'M', '09 Bayside Plaza', '1931-05-31');
INSERT INTO PetOwner VALUES ('Koral', 'Alayne', 'aclimofn@blogs.com', 'g6duJT', '2017-03-26', 'false', 'F', '3 Wayridge Drive', '1990-08-11');
INSERT INTO PetOwner VALUES ('Pier', 'Kimberli', 'kglidefo@goodreads.com', '2ZbdLhsa', '2005-03-31', 'true', 'F', '74274 Vahlen Lane', '1974-02-01');
INSERT INTO PetOwner VALUES ('Loria', 'Kip', 'kedmandsfp@noaa.gov', 'blwX9HfW5GCr', '2019-02-06', 'false', 'F', '11 Fallview Hill', '2004-01-25');
INSERT INTO PetOwner VALUES ('Lu', 'Beret', 'blottefq@cdbaby.com', 'lTgrlbw', '2016-07-31', 'false', 'F', '8978 Barby Road', '1940-08-26');
INSERT INTO PetOwner VALUES ('Reinold', 'Crosby', 'coliverasfr@marriott.com', 'YzGcjZ2uSlG', '2013-09-12', 'false', 'M', '70 Farmco Court', '1944-10-31');
INSERT INTO PetOwner VALUES ('Mallory', 'Haslett', 'hcarhartfs@dell.com', 'F77IZN0Aoo', '2002-04-01', 'false', 'M', '97 Truax Terrace', '1971-03-03');
INSERT INTO PetOwner VALUES ('Ruthy', 'Latia', 'lcollabinefu@amazon.co.uk', 'O2cHDEn', '2015-08-02', 'false', 'F', '9 Rigney Court', '1963-09-25');
INSERT INTO PetOwner VALUES ('Brig', 'Ringo', 'rswinnardfv@lycos.com', '6xQ68T', '2010-09-05', 'false', 'M', '8 Armistice Place', '1965-08-05');
INSERT INTO PetOwner VALUES ('Rinaldo', 'Waylen', 'wcraykefw@irs.gov', 'mdBYR6oCYqd', '2002-03-10', 'true', 'M', '727 Westend Avenue', '1972-12-22');
INSERT INTO PetOwner VALUES ('Millard', 'Leon', 'lmaytumfx@php.net', 'oeyOBoy', '2016-07-30', 'true', 'M', '3 Nelson Pass', '1946-04-02');
INSERT INTO PetOwner VALUES ('Fianna', 'Odelle', 'oelijahufy@github.com', 'P7CJgf', '2017-01-10', 'true', 'F', '578 Knutson Point', '1984-10-23');
INSERT INTO PetOwner VALUES ('Julie', 'Eba', 'emcronaldfz@ucoz.com', 'PY3Dt9qP1YV', '2019-12-30', 'false', 'F', '02901 Warrior Hill', '1954-02-09');
INSERT INTO PetOwner VALUES ('Evonne', 'Loren', 'lasberyg0@homestead.com', 'raDpVeYVXh7G', '2019-11-25', 'false', 'F', '6 Bluejay Pass', '1953-05-10');
INSERT INTO PetOwner VALUES ('Jeffie', 'Bernardo', 'bpavlovskyg1@sun.com', '5KVQtKuqAw', '2008-12-14', 'false', 'M', '9 Duke Alley', '1990-09-12');
INSERT INTO PetOwner VALUES ('Tonye', 'Letitia', 'lcornnerg2@webs.com', '7SrpRUtU4G', '2015-03-01', 'true', 'F', '0 Mayer Drive', '1984-03-28');
INSERT INTO PetOwner VALUES ('Gretal', 'Mada', 'mtallisg3@storify.com', 'trjMN7', '2003-05-18', 'false', 'F', '517 Crescent Oaks Place', '1950-01-24');
INSERT INTO PetOwner VALUES ('Mercie', 'Sibella', 'sguageg4@cornell.edu', '0mEjq8Bdh7g', '2006-02-25', 'true', 'F', '9 Transport Plaza', '1998-10-08');
INSERT INTO PetOwner VALUES ('Paxton', 'Joseito', 'jstockwellg5@harvard.edu', 'jWi3B5Mu', '2005-12-11', 'false', 'M', '1823 Tomscot Trail', '1932-05-30');
INSERT INTO PetOwner VALUES ('Celle', 'Allyson', 'agiggg7@salon.com', 'csoRc3', '2020-09-23', 'true', 'F', '782 Badeau Way', '2006-02-16');
INSERT INTO PetOwner VALUES ('Talbot', 'Archibaldo', 'aciccog8@networkadvertising.org', 'ViBQy2lH', '2015-05-23', 'true', 'M', '634 Bowman Lane', '1945-06-13');
INSERT INTO PetOwner VALUES ('Germayne', 'Laney', 'lcalbertg9@loc.gov', 'tYSp6nwrY', '2008-12-14', 'false', 'M', '55 Killdeer Avenue', '1975-01-27');
INSERT INTO PetOwner VALUES ('Judith', 'Aubrette', 'adowkerga@sourceforge.net', 'rG6tQxSXe2', '2015-08-29', 'true', 'F', '5 Magdeline Way', '1953-02-08');
INSERT INTO PetOwner VALUES ('Erwin', 'Taddeo', 'tthonasongb@tuttocitta.it', 'pOgb3uu', '2013-10-14', 'true', 'M', '9165 Park Meadow Hill', '1967-08-19');
INSERT INTO PetOwner VALUES ('Ario', 'Hartwell', 'hangiergc@hibu.com', 'oWmwRC2I5', '2004-08-15', 'true', 'M', '9 6th Alley', '1943-07-31');
INSERT INTO PetOwner VALUES ('Maddy', 'Obediah', 'ostowergd@stumbleupon.com', 'KU7aRf2oT', '2019-08-14', 'true', 'M', '34 Swallow Crossing', '1992-09-02');
INSERT INTO PetOwner VALUES ('Trude', 'Mariel', 'mstollenbergge@ow.ly', 'yA9RW4k', '2005-05-05', 'true', 'F', '387 Pearson Place', '1968-12-04');
INSERT INTO PetOwner VALUES ('Buffy', 'Janene', 'jknellergf@goodreads.com', 'rLBWIbhfVU', '2014-07-30', 'false', 'F', '8 Tennessee Alley', '2005-12-03');
INSERT INTO PetOwner VALUES ('Torrin', 'Cam', 'cbellissgg@indiatimes.com', 'yLYqdDYf0u', '2014-03-24', 'true', 'M', '1 Maryland Street', '1983-08-10');
INSERT INTO PetOwner VALUES ('Kathe', 'Hanni', 'hchitsongh@blogs.com', 'jsiwzq', '2003-06-28', 'false', 'F', '91 Merry Parkway', '1998-05-12');
INSERT INTO PetOwner VALUES ('Purcell', 'Derrick', 'dbaudouxgi@feedburner.com', 'Xhm37nC', '2004-10-05', 'true', 'M', '6 Mitchell Terrace', '2016-03-08');
INSERT INTO PetOwner VALUES ('Kenton', 'Osborne', 'okelingegj@shop-pro.jp', '9CGt7a', '2005-11-06', 'false', 'M', '850 Oakridge Park', '1940-08-20');
INSERT INTO PetOwner VALUES ('Tabby', 'Gun', 'gblessedgk@newsvine.com', 'Oz5rHY', '2019-04-09', 'false', 'M', '966 Hudson Pass', '1984-05-20');
INSERT INTO PetOwner VALUES ('Caldwell', 'Paul', 'preymersgl@cpanel.net', '9uXXGOe', '2012-03-27', 'true', 'M', '077 Stoughton Court', '1988-06-26');
INSERT INTO PetOwner VALUES ('Phylis', 'Demetris', 'dtrengrovegm@cnet.com', 'YJnNuu', '2011-09-08', 'false', 'F', '67 Bonner Crossing', '1964-01-04');
INSERT INTO PetOwner VALUES ('Aubrey', 'Jo-anne', 'jbitchenergn@themeforest.net', 'bSoqMxLC44z9', '2006-04-19', 'false', 'F', '809 Acker Circle', '1958-04-10');
INSERT INTO PetOwner VALUES ('Camella', 'Shayla', 'smccarrongo@sciencedirect.com', 'nrZIvc2i', '2005-04-03', 'false', 'F', '68 Merrick Point', '1972-07-06');
INSERT INTO PetOwner VALUES ('Malva', 'Melesa', 'mheartfieldgp@dailymotion.com', '5hZSeip', '2001-09-22', 'false', 'F', '11265 Fremont Street', '1935-09-18');
INSERT INTO PetOwner VALUES ('Feodor', 'Andrey', 'aklaffsgq@studiopress.com', 'hGX0Keik6fN', '2018-09-13', 'false', 'M', '61627 Stoughton Place', '2001-01-18');
INSERT INTO PetOwner VALUES ('Ardelis', 'Joellen', 'joxtongr@friendfeed.com', 'KAUryBav', '2002-08-22', 'false', 'F', '46 Swallow Plaza', '1938-04-11');
INSERT INTO PetOwner VALUES ('Duffy', 'Hobart', 'hstrutegs@ed.gov', 'Rk8nHGk', '2001-05-08', 'true', 'M', '0739 Comanche Hill', '1934-01-07');
INSERT INTO PetOwner VALUES ('Reggi', 'Elinor', 'ereijmersgt@aol.com', 'Ll4M2H', '2014-11-01', 'true', 'F', '6 Green Crossing', '1946-07-08');
INSERT INTO PetOwner VALUES ('Aldrich', 'Dudley', 'danstisgu@ca.gov', '1bSK0dqCS', '2008-03-22', 'false', 'M', '28598 Fremont Trail', '1941-12-12');
INSERT INTO PetOwner VALUES ('Royce', 'Philip', 'pmaylorgv@thetimes.co.uk', 'jpVQZjSKFA', '2014-10-16', 'false', 'M', '15224 Hallows Lane', '2012-03-15');
INSERT INTO PetOwner VALUES ('Caesar', 'Mathian', 'mfoystongw@dion.ne.jp', 'MtZchcPEJ', '2014-09-20', 'false', 'M', '4 Brentwood Street', '1963-08-04');
INSERT INTO PetOwner VALUES ('Lillis', 'Rhody', 'roillergx@sakura.ne.jp', 'nGNTlulUOT', '2012-12-15', 'true', 'F', '560 Donald Alley', '1950-10-12');
INSERT INTO PetOwner VALUES ('Julianna', 'Clara', 'cdomangy@vistaprint.com', 'j5mp4YYx', '2004-06-21', 'true', 'F', '74 Vera Crossing', '1950-10-11');
INSERT INTO PetOwner VALUES ('Nero', 'Ravid', 'rdonhardtgz@vk.com', 'fuMJwLmc1hyc', '2009-03-17', 'false', 'M', '93209 Paget Junction', '2014-11-09');
INSERT INTO PetOwner VALUES ('Matthus', 'Maurie', 'meyeh0@paginegialle.it', 'khUlAa', '2011-04-16', 'true', 'M', '436 Southridge Drive', '2004-11-28');
INSERT INTO PetOwner VALUES ('Arabel', 'Lorilyn', 'laronsonh1@mozilla.com', 'LHSdP4Q', '2009-08-10', 'true', 'F', '7 Randy Place', '1930-12-18');
INSERT INTO PetOwner VALUES ('Slade', 'Wayne', 'wchesswash2@blogs.com', '075BUF74tIy', '2005-03-20', 'true', 'M', '1 Judy Court', '2000-07-01');
INSERT INTO PetOwner VALUES ('Martguerita', 'Elinore', 'ebarnesh3@elegantthemes.com', 'rOs8NiwNc', '2020-05-15', 'true', 'F', '73468 Garrison Street', '2019-12-23');
INSERT INTO PetOwner VALUES ('Regan', 'Neall', 'nibbetth4@ft.com', 'y6OatP', '2010-12-17', 'false', 'M', '99242 Gateway Street', '1981-11-24');
INSERT INTO PetOwner VALUES ('Judd', 'Wendall', 'wturleyh5@dedecms.com', 'LBcOkgo', '2011-03-05', 'false', 'M', '58331 Lakeland Drive', '2004-06-24');
INSERT INTO PetOwner VALUES ('Cthrine', 'Mia', 'mcapeloffh6@springer.com', 'dd47JlldGvo', '2006-05-18', 'true', 'F', '6504 Anhalt Street', '1940-03-04');
INSERT INTO PetOwner VALUES ('Ennis', 'Massimo', 'mrosenthalh7@hexun.com', 'AXQd5mo', '2011-12-22', 'true', 'M', '7 Bunting Place', '1965-11-19');
INSERT INTO PetOwner VALUES ('Abdel', 'Ignace', 'iswinburneh9@sitemeter.com', '6V09GFUy', '2012-05-23', 'true', 'M', '386 Hooker Place', '1988-10-06');
INSERT INTO PetOwner VALUES ('Stefano', 'Puff', 'pmcgreilha@aboutads.info', 'UPRcnDkn41p', '2012-06-07', 'false', 'M', '801 Sommers Parkway', '1989-11-11');
INSERT INTO PetOwner VALUES ('Leslie', 'Mattie', 'mmorelandhb@pcworld.com', 'urgozLq1', '2002-05-27', 'true', 'F', '1 Butternut Road', '2000-12-06');
INSERT INTO PetOwner VALUES ('Tabb', 'Hamel', 'hlabbethc@marketwatch.com', '57ExmkDv72', '2012-07-14', 'true', 'M', '112 Lyons Place', '2006-04-21');
INSERT INTO PetOwner VALUES ('Nona', 'Christiana', 'cbollomhd@ezinearticles.com', 'qaEa6Wa9R', '2001-12-04', 'false', 'F', '712 Straubel Terrace', '1931-06-14');
INSERT INTO PetOwner VALUES ('Phaidra', 'Noel', 'ngofforthhe@smh.com.au', 'G5lJsGWU', '2007-04-09', 'true', 'F', '3110 Crescent Oaks Street', '1971-10-19');
INSERT INTO PetOwner VALUES ('Constantino', 'Artur', 'aobradainhf@spotify.com', 'InndhXx1Gbj', '2017-07-09', 'true', 'M', '0 Esker Pass', '1950-11-27');
INSERT INTO PetOwner VALUES ('Rowney', 'Gerrie', 'gfairburnhg@gizmodo.com', 'GMDt5cfFa', '2019-08-08', 'true', 'M', '4 Portage Parkway', '1936-11-09');
INSERT INTO PetOwner VALUES ('Vivian', 'Rebeca', 'rkrzysztofiakhh@gnu.org', 'NuRMLjwZNypG', '2011-10-09', 'true', 'F', '9582 Texas Center', '2007-08-31');
INSERT INTO PetOwner VALUES ('Shalom', 'Ange', 'abearehi@dedecms.com', 'h6oK89OQ', '2006-04-09', 'true', 'M', '292 Moose Alley', '1987-04-27');
INSERT INTO PetOwner VALUES ('Dacey', 'Nisse', 'npetrozzihj@google.com.hk', 'QWPQmTmuxpE', '2007-01-20', 'true', 'F', '272 Forest Drive', '1951-10-13');
INSERT INTO PetOwner VALUES ('Haily', 'Maddie', 'mhaggarhk@umn.edu', 'QxjOF5q', '2014-06-07', 'false', 'F', '511 Dovetail Trail', '1994-07-20');
INSERT INTO PetOwner VALUES ('Kellyann', 'Leyla', 'lholtonhl@weibo.com', '0xMOJTuFV', '2005-10-24', 'true', 'F', '780 Merchant Parkway', '2016-04-06');
INSERT INTO PetOwner VALUES ('Helge', 'Casi', 'chuntarhm@barnesandnoble.com', 'kDOMHKVCc0f', '2013-01-27', 'true', 'F', '09086 Evergreen Point', '1984-12-03');
INSERT INTO PetOwner VALUES ('Cati', 'Kay', 'kspaingowerhn@bizjournals.com', 'da36SkgrFn8', '2003-05-16', 'false', 'F', '53417 Mcguire Drive', '1995-03-07');
INSERT INTO PetOwner VALUES ('Wildon', 'Spenser', 'somonahanho@timesonline.co.uk', 'f5zCFO2tO', '2019-11-21', 'false', 'M', '98325 Kensington Park', '2006-08-10');
INSERT INTO PetOwner VALUES ('Margaretha', 'Evonne', 'epayshp@merriam-webster.com', 'Rk8MmMHwOE4T', '2012-10-08', 'true', 'F', '05704 Hollow Ridge Drive', '1975-03-04');
INSERT INTO PetOwner VALUES ('Quinn', 'Tiebout', 'tduffetthq@springer.com', 'kZxxVM', '2020-01-25', 'true', 'M', '780 Veith Point', '2019-12-26');
INSERT INTO PetOwner VALUES ('Harper', 'Augustus', 'adennisshr@statcounter.com', 'HQY3W6', '2011-05-18', 'false', 'M', '6 East Circle', '1999-10-12');
INSERT INTO PetOwner VALUES ('Nikkie', 'Sheila', 'ssteagallhs@wikipedia.org', 'M9vrSLLU', '2013-08-28', 'false', 'F', '903 Gale Center', '1971-10-31');
INSERT INTO PetOwner VALUES ('Mischa', 'Frasier', 'fschwandenht@reference.com', 'S8oEnvV', '2015-09-19', 'true', 'M', '29371 Wayridge Terrace', '2017-02-17');
INSERT INTO PetOwner VALUES ('Odille', 'Kordula', 'kmckinlesshu@quantcast.com', 'LulAbdyhC', '2017-02-09', 'true', 'F', '04840 Melrose Way', '1971-12-10');
INSERT INTO PetOwner VALUES ('Jackqueline', 'Modestia', 'mjanderahw@dot.gov', 'HmAT7UO', '2001-06-01', 'true', 'F', '969 Valley Edge Street', '2011-05-28');
INSERT INTO PetOwner VALUES ('Micah', 'Maddie', 'mcotgrovehx@digg.com', 'zR2VDzy68', '2015-01-20', 'false', 'M', '9357 Almo Avenue', '1953-01-25');
INSERT INTO PetOwner VALUES ('Mauricio', 'Ban', 'bsaziohy@smugmug.com', 'rlWNKzrM0U6', '2019-04-03', 'true', 'M', '61 Dovetail Avenue', '2003-08-31');
INSERT INTO PetOwner VALUES ('Dyanna', 'Marieann', 'mkearsleyhz@xing.com', '42vjgkZUcFi7', '2004-09-22', 'false', 'F', '617 Hoepker Circle', '1941-12-18');
INSERT INTO PetOwner VALUES ('Letty', 'Zena', 'zcurcheri0@sphinn.com', '35DP0hi', '2003-12-24', 'false', 'F', '0528 Stone Corner Plaza', '1997-07-14');
INSERT INTO PetOwner VALUES ('Wynne', 'Kati', 'krossanti1@google.com.hk', 'WPEr2tG', '2012-12-05', 'true', 'F', '80452 Delladonna Hill', '1946-02-07');
INSERT INTO PetOwner VALUES ('Moina', 'Nani', 'nmurbyi2@psu.edu', 'jKAtGkT', '2001-06-02', 'true', 'F', '9294 Derek Hill', '1977-08-02');
INSERT INTO PetOwner VALUES ('Gabey', 'Demetria', 'dreavelli3@tinyurl.com', 'XYhkBVWAFS', '2008-04-03', 'true', 'F', '2542 North Center', '1943-03-05');
INSERT INTO PetOwner VALUES ('Lulu', 'Terri', 'trosentholeri4@canalblog.com', 'BEfXl4BUfU', '2002-07-03', 'true', 'F', '3 Nevada Place', '1939-05-01');
INSERT INTO PetOwner VALUES ('Nettie', 'Lira', 'ldavisi5@npr.org', 'zTo7EgrVbL', '2000-12-07', 'true', 'F', '962 5th Alley', '1935-01-05');
INSERT INTO PetOwner VALUES ('Glenna', 'Joelynn', 'jdeavillei6@vkontakte.ru', '4TWqoff', '2009-09-20', 'false', 'F', '26 Messerschmidt Parkway', '1940-04-17');
INSERT INTO PetOwner VALUES ('Albina', 'Anthe', 'alemanui7@chronoengine.com', '4FVyRus7y', '2006-04-16', 'true', 'F', '57339 American Ash Lane', '1975-10-09');
INSERT INTO PetOwner VALUES ('Gino', 'Garwood', 'gpowletti8@weibo.com', 'LITGg9', '2001-03-07', 'false', 'M', '8 Northview Junction', '1950-03-08');
INSERT INTO PetOwner VALUES ('Keenan', 'Jody', 'jconstablei9@newyorker.com', 'flHtnzV', '2002-01-02', 'true', 'M', '5307 Paget Point', '1992-09-27');
INSERT INTO PetOwner VALUES ('Leola', 'Blondie', 'bbishia@hugedomains.com', 'dnetfMCCI51', '2019-05-16', 'false', 'F', '11370 Novick Drive', '1964-05-19');
INSERT INTO PetOwner VALUES ('Hamid', 'Giffie', 'gmabenib@usa.gov', 'VtC7okvlGKrQ', '2015-02-05', 'true', 'M', '777 Main Street', '1947-07-22');
INSERT INTO PetOwner VALUES ('Smith', 'Cesaro', 'cfranceschic@merriam-webster.com', 'c2bZPVN', '2003-11-09', 'false', 'M', '558 Arrowood Plaza', '1998-05-25');
INSERT INTO PetOwner VALUES ('Armstrong', 'Butch', 'bdikelsid@washington.edu', 'tqv8kTPNuW', '2018-06-15', 'true', 'M', '8 Gerald Parkway', '1938-03-27');
INSERT INTO PetOwner VALUES ('Madison', 'Slade', 'ssturgessie@elegantthemes.com', 'pk2VrX', '2014-11-25', 'true', 'M', '392 Lillian Circle', '1937-09-23');
INSERT INTO PetOwner VALUES ('Leesa', 'Louisa', 'ldommif@imgur.com', 'gbVE1pd', '2004-10-24', 'true', 'F', '7220 Jenna Park', '1978-04-26');
INSERT INTO PetOwner VALUES ('Alleyn', 'Staford', 'shenckeig@istockphoto.com', 'NvkB8GR', '2007-07-08', 'true', 'M', '10291 Continental Road', '1976-11-10');
INSERT INTO PetOwner VALUES ('Anatol', 'Lucian', 'lfeatherbyih@japanpost.jp', 'IduB8RO2VMoh', '2019-12-31', 'false', 'M', '7 Veith Center', '1935-10-29');
INSERT INTO PetOwner VALUES ('Levi', 'Shell', 'scousansii@nymag.com', 'DNcVV5', '2014-09-26', 'true', 'M', '18150 Elmside Crossing', '1990-06-28');
INSERT INTO PetOwner VALUES ('Georgi', 'Lonnie', 'lricharsonij@usnews.com', 'DkO2Q6KT', '2017-09-23', 'true', 'M', '8600 Springs Trail', '2000-09-19');
INSERT INTO PetOwner VALUES ('Fairfax', 'Caleb', 'cfranciottiik@yahoo.com', 'M6NILz', '2013-06-25', 'false', 'M', '1061 Knutson Lane', '1995-05-11');
INSERT INTO PetOwner VALUES ('Babb', 'Brittaney', 'bshambrokeil@skyrock.com', 'xiLucCmD9XL', '2013-09-14', 'true', 'F', '755 Morning Crossing', '1967-02-13');
INSERT INTO PetOwner VALUES ('Leyla', 'Mair', 'mcogleyim@zimbio.com', 'Wsute07HZWa', '2009-07-21', 'false', 'F', '82975 Eggendart Place', '1940-02-18');
INSERT INTO PetOwner VALUES ('Renaud', 'Lucien', 'lsmalmanin@over-blog.com', '0R9vqs', '2020-07-22', 'false', 'M', '81773 Cody Trail', '1968-03-10');
INSERT INTO PetOwner VALUES ('Betteann', 'Anjela', 'akoomario@php.net', 'p1ORAQv', '2014-05-09', 'false', 'F', '3 Hanson Drive', '1945-12-10');
INSERT INTO PetOwner VALUES ('Pamela', 'Rubetta', 'rjertzip@squarespace.com', 'BikLrk', '2004-07-10', 'false', 'F', '12488 Dwight Road', '2011-01-24');
INSERT INTO PetOwner VALUES ('Ondrea', 'Jaine', 'jvedyashkiniq@netscape.com', 'dWpBhAEQIB', '2008-01-07', 'false', 'F', '5 Helena Place', '1938-05-14');
INSERT INTO PetOwner VALUES ('Ferdinanda', 'Paulina', 'pgostlingir@timesonline.co.uk', 'cQnFQ8uV', '2016-10-31', 'true', 'F', '98732 East Terrace', '1999-07-13');
INSERT INTO PetOwner VALUES ('Arney', 'Ahmed', 'agerritis@opera.com', 'TWD1tsRM', '2019-01-23', 'false', 'M', '656 Crescent Oaks Way', '2009-07-31');
INSERT INTO PetOwner VALUES ('Harrie', 'Theresita', 'tlengthornit@google.com.au', 'TCQwVUGMoFg', '2004-04-08', 'false', 'F', '75842 Canary Trail', '1947-04-06');
INSERT INTO PetOwner VALUES ('Klemens', 'Nickolaus', 'ngillingiu@va.gov', 'U2PHAY', '2006-02-15', 'false', 'M', '304 Autumn Leaf Point', '1984-12-15');
INSERT INTO PetOwner VALUES ('Lari', 'Kit', 'kdurdleiv@boston.com', '2cpKZ3IPmIL', '2004-10-13', 'true', 'F', '55150 Old Gate Way', '1982-02-03');
INSERT INTO PetOwner VALUES ('Ambrosius', 'Loy', 'lpadgettiw@google.it', 'kNxuA99hO', '2013-06-10', 'false', 'M', '45660 Coleman Park', '1966-10-03');
INSERT INTO PetOwner VALUES ('Estrellita', 'Emmie', 'edellascalaix@scientificamerican.com', 'rrsivRpfh', '2016-02-20', 'true', 'F', '507 East Park', '1998-08-17');
INSERT INTO PetOwner VALUES ('Marie', 'Elnora', 'ebringloeiy@indiatimes.com', 'EvPCZhRCO', '2005-12-20', 'false', 'F', '61 Eastwood Hill', '1986-10-28');
INSERT INTO PetOwner VALUES ('Maxie', 'Roscoe', 'rmanniniz@reuters.com', 'KoZa78jcoMJr', '2007-10-29', 'true', 'M', '067 Melby Parkway', '1953-10-16');
INSERT INTO PetOwner VALUES ('Ianthe', 'Meagan', 'mfoulkesj1@bbb.org', 'cw1aw6o', '2002-04-22', 'true', 'F', '351 Haas Avenue', '1999-07-23');
INSERT INTO PetOwner VALUES ('Grata', 'Avie', 'alunoj2@vkontakte.ru', 'sZZJHsmY', '2007-12-02', 'false', 'F', '190 Clove Road', '2005-08-03');
INSERT INTO PetOwner VALUES ('Isabelle', 'Barbette', 'bsheringtonj3@t.co', '8dY24iKc', '2009-07-10', 'true', 'F', '0 Steensland Circle', '1965-05-22');
INSERT INTO PetOwner VALUES ('Anabal', 'Carroll', 'cscullyj4@wikia.com', 'Vd0P6Z', '2002-08-27', 'false', 'F', '6758 Moulton Alley', '1993-01-08');
INSERT INTO PetOwner VALUES ('Rubia', 'Ashlan', 'aloadwickj5@redcross.org', 'YWmxiUrgOx6', '2017-10-23', 'false', 'F', '8 American Circle', '2020-01-15');
INSERT INTO PetOwner VALUES ('Shannon', 'Wit', 'wratterj6@ow.ly', 'RQYDz8r6Dzr', '2009-06-16', 'false', 'M', '62074 Portage Lane', '1998-11-18');
INSERT INTO PetOwner VALUES ('Judon', 'Marcello', 'mhoveej7@eepurl.com', 'Oy2LNVDdVl', '2006-09-08', 'true', 'M', '1233 Sherman Crossing', '1935-10-08');
INSERT INTO PetOwner VALUES ('Annetta', 'Cynthea', 'cdowyerj8@nasa.gov', 'moDOTB0Pmh', '2010-04-08', 'true', 'F', '36 Hallows Trail', '1934-12-09');
INSERT INTO PetOwner VALUES ('Merrile', 'Frances', 'fduddenj9@barnesandnoble.com', 'AhWcV1', '2007-05-27', 'false', 'F', '030 Debra Plaza', '1981-11-27');
INSERT INTO PetOwner VALUES ('Doll', 'Ki', 'kgorriessenja@freewebs.com', 'gUp0Tdzl22', '2005-09-19', 'true', 'F', '38 Muir Terrace', '1957-06-26');
INSERT INTO PetOwner VALUES ('Gwyn', 'Kerry', 'kscarsbrickjb@artisteer.com', 'bs1YVFP3iCjO', '2002-11-08', 'false', 'F', '391 Jenna Lane', '1937-02-20');
INSERT INTO PetOwner VALUES ('Cherye', 'Kinna', 'kbillingejc@weebly.com', 'zy7EFEq8Odoj', '2003-01-08', 'true', 'F', '6 Larry Street', '1945-12-21');
INSERT INTO PetOwner VALUES ('Gavrielle', 'Velvet', 'vbowlingjd@51.la', 'heJ3rdY9', '2011-06-15', 'true', 'F', '5500 Carioca Pass', '1976-10-11');
INSERT INTO PetOwner VALUES ('Abbi', 'Zia', 'zgilvaryje@ucoz.com', 'UwopK0E0ey', '2016-04-15', 'false', 'F', '8 Esker Circle', '1971-02-13');
INSERT INTO PetOwner VALUES ('Lorenza', 'Trixy', 'thoferjf@4shared.com', '2KkFUZiQDfO2', '2010-11-01', 'false', 'F', '156 North Place', '1958-03-06');
INSERT INTO PetOwner VALUES ('Angie', 'Neala', 'nmcgouganjg@huffingtonpost.com', 'Vo3tTvRpHz', '2016-07-11', 'false', 'F', '5 Little Fleur Place', '1960-02-05');
INSERT INTO PetOwner VALUES ('Johnnie', 'Glynn', 'gsagejh@free.fr', 'wQ8tVJYko6', '2003-03-06', 'true', 'M', '1481 Summerview Park', '1968-10-19');
INSERT INTO PetOwner VALUES ('Jory', 'Tristam', 'tgladecheji@github.com', 'shfMNxrL0E', '2011-05-03', 'true', 'M', '28685 Commercial Lane', '1943-11-04');
INSERT INTO PetOwner VALUES ('Alley', 'Gregoire', 'gstubsjj@tumblr.com', 'Hn1Hv2', '2011-06-04', 'true', 'M', '9 Forest Run Point', '1955-07-10');
INSERT INTO PetOwner VALUES ('Silvia', 'Leilah', 'lkrabbejk@adobe.com', 'J8izE7Nm7', '2020-02-25', 'false', 'F', '53 Oxford Park', '1963-08-02');
INSERT INTO PetOwner VALUES ('Sawyere', 'Pascale', 'psawfordejm@ox.ac.uk', 'AxYH8wFMgDJ', '2020-03-03', 'true', 'M', '3 8th Street', '1974-11-12');
INSERT INTO PetOwner VALUES ('Benni', 'Imelda', 'iandrionijn@mapy.cz', 'C2Uvtrx', '2004-01-08', 'true', 'F', '430 Lakewood Gardens Circle', '1985-05-09');
INSERT INTO PetOwner VALUES ('Marijn', 'Domenico', 'ddomercjo@xinhuanet.com', '3i6EDikE', '2016-08-21', 'true', 'M', '3132 Delaware Place', '1931-07-06');
INSERT INTO PetOwner VALUES ('Jacklyn', 'Ira', 'iadkinjp@cbslocal.com', 'n7vUfZZ1o', '2007-12-17', 'true', 'F', '557 Pine View Street', '1987-03-06');
INSERT INTO PetOwner VALUES ('Arri', 'Jeno', 'jchreejq@bravesites.com', 'fUFA58AzTj6', '2005-01-07', 'true', 'M', '0814 Lunder Junction', '1945-05-07');
INSERT INTO PetOwner VALUES ('Cherianne', 'Hannie', 'hbonneyjr@miibeian.gov.cn', '1ivBO2kydBzU', '2014-06-15', 'true', 'F', '75 Anhalt Crossing', '2019-10-06');
INSERT INTO PetOwner VALUES ('Hermy', 'Ronnie', 'rtampinjs@wikia.com', '4X1XZs', '2001-08-07', 'true', 'M', '75 Golf View Circle', '1966-12-22');
INSERT INTO PetOwner VALUES ('Beverlie', 'Debera', 'dmocharjt@jalbum.net', 'CcXE1ic', '2020-07-10', 'false', 'F', '90921 Reindahl Place', '1999-12-17');
INSERT INTO PetOwner VALUES ('Sid', 'Florian', 'fblakelockju@w3.org', 'LV3jUhsTR', '2018-09-04', 'false', 'M', '2 Continental Plaza', '1991-06-05');
INSERT INTO PetOwner VALUES ('Robin', 'Garvey', 'gbartoljv@nba.com', 'zNQOgvzaE6', '2009-11-21', 'false', 'M', '31 Marcy Terrace', '2019-04-23');
INSERT INTO PetOwner VALUES ('Sheila-kathryn', 'Joelie', 'jtregidgojw@newyorker.com', '4h2uvLXgvuZ', '2007-09-17', 'false', 'F', '7884 Vernon Drive', '1994-07-18');
INSERT INTO PetOwner VALUES ('Zedekiah', 'Averell', 'areiachjx@dailymail.co.uk', 'Y7lJsteE0D', '2018-03-21', 'true', 'M', '3 Montana Street', '1969-12-31');
INSERT INTO PetOwner VALUES ('Xerxes', 'Zerk', 'zneilanjy@4shared.com', 'GimycSYy7', '2003-01-24', 'true', 'M', '34 Arkansas Street', '1969-11-23');
INSERT INTO PetOwner VALUES ('Pavlov', 'Duncan', 'dglenjz@hugedomains.com', 'USSp4k', '2012-02-22', 'true', 'M', '8 Hermina Hill', '1975-06-13');
INSERT INTO PetOwner VALUES ('Tanney', 'Xever', 'xkarpeevk0@jugem.jp', 'jh9veQ', '2014-04-24', 'true', 'M', '456 Arrowood Hill', '1949-06-11');
INSERT INTO PetOwner VALUES ('Gloriana', 'Reena', 'ralabastark1@opera.com', 'YWZX6gKY3E', '2004-02-26', 'false', 'F', '97100 Moulton Plaza', '1945-06-08');
INSERT INTO PetOwner VALUES ('Moritz', 'Pearce', 'pwooffindenk2@answers.com', 'OfKu4o', '2015-08-17', 'true', 'M', '43 Dunning Pass', '1933-08-03');
INSERT INTO PetOwner VALUES ('Allard', 'Faber', 'ftompsettk3@phpbb.com', 'OJDf3UP', '2020-03-27', 'false', 'M', '28279 Bashford Drive', '2000-08-29');
INSERT INTO PetOwner VALUES ('Cairistiona', 'Rae', 'rhawneyk4@photobucket.com', 'p8y3N3yOSIaJ', '2019-07-01', 'false', 'F', '96 Arrowood Plaza', '1976-04-04');
INSERT INTO PetOwner VALUES ('Harcourt', 'Chauncey', 'ccastillonk5@newyorker.com', 'ti01EM', '2010-11-22', 'true', 'M', '10 Old Gate Plaza', '2003-05-24');
INSERT INTO PetOwner VALUES ('Matti', 'Tine', 'tmaxsteadk6@php.net', '8SExt3', '2017-09-13', 'false', 'F', '4 Hoepker Point', '1959-02-06');
INSERT INTO PetOwner VALUES ('Whit', 'Nolan', 'nrainsdenk7@cpanel.net', 'RcyF7X', '2005-11-19', 'true', 'M', '875 7th Parkway', '1952-08-08');
INSERT INTO PetOwner VALUES ('Marnia', 'Lindie', 'ltommaseok8@list-manage.com', '99XF5g', '2009-09-30', 'true', 'F', '27 Reinke Crossing', '1945-11-23');
INSERT INTO PetOwner VALUES ('Milli', 'Nada', 'nlinkk9@gnu.org', 'c1sZCFOP1d', '2013-08-30', 'true', 'F', '0621 Bultman Crossing', '1972-03-23');
INSERT INTO PetOwner VALUES ('Ede', 'Dosi', 'dneenanka@mac.com', '8qVV2T5pv5i9', '2007-01-03', 'true', 'F', '19769 Brentwood Circle', '2004-01-19');
INSERT INTO PetOwner VALUES ('Nanny', 'Clerissa', 'cemanulssonkb@marketwatch.com', 'mNvwYEEZBL', '2004-03-17', 'true', 'F', '16438 Fuller Pass', '1951-04-22');
INSERT INTO PetOwner VALUES ('Althea', 'Aviva', 'avollethkc@nytimes.com', 'JAqqtc8', '2013-01-05', 'false', 'F', '2414 Sunfield Center', '1950-08-17');
INSERT INTO PetOwner VALUES ('Berne', 'Mikael', 'mmcquirterke@dedecms.com', 'zCqykBI', '2014-11-23', 'true', 'M', '03 Straubel Park', '1999-02-28');
INSERT INTO PetOwner VALUES ('Dennie', 'Leanna', 'lcaldronkf@slashdot.org', 'yRGcYqEmxv', '2013-02-01', 'true', 'F', '856 Mandrake Trail', '1994-10-30');
INSERT INTO PetOwner VALUES ('Ellwood', 'Wolfy', 'wkoskg@taobao.com', 'zFIeV3g', '2015-10-21', 'false', 'M', '6636 Paget Junction', '1976-04-24');
INSERT INTO PetOwner VALUES ('Cornie', 'Ashlen', 'afolliskh@cmu.edu', 'PT2UzeH', '2011-10-15', 'false', 'F', '517 Paget Plaza', '1971-07-01');
INSERT INTO PetOwner VALUES ('Ulrica', 'Daphene', 'dsickamoreki@webs.com', 'n6z5Ep6vSmQ8', '2000-12-25', 'false', 'F', '1829 Blue Bill Park Place', '1974-04-30');
INSERT INTO PetOwner VALUES ('Georas', 'Eli', 'emcfadyenkj@archive.org', 'b3XCibqhx', '2011-02-04', 'true', 'M', '05575 Eggendart Pass', '1984-01-08');
INSERT INTO PetOwner VALUES ('Pattin', 'Flory', 'fsandifordkk@goodreads.com', 'xE15aF', '2016-10-28', 'true', 'M', '203 Forest Dale Street', '1947-07-14');
INSERT INTO PetOwner VALUES ('Roselle', 'Vivianne', 'vcogdellkl@icio.us', 'UguGzv8ef', '2010-07-31', 'true', 'F', '1577 Myrtle Plaza', '1932-09-27');
INSERT INTO PetOwner VALUES ('Odetta', 'Abbi', 'aridgwaykm@google.com.hk', 'y6itGY', '2007-08-19', 'true', 'F', '41 Myrtle Place', '1990-10-17');
INSERT INTO PetOwner VALUES ('Ag', 'Erinn', 'egagerkn@webnode.com', 'oiN4lHiZ', '2014-10-14', 'false', 'F', '38091 Mesta Point', '1935-02-25');
INSERT INTO PetOwner VALUES ('Carlie', 'Buiron', 'bmacgeaneyko@about.me', 'BFPymD1S7f1p', '2007-10-26', 'false', 'M', '557 Riverside Lane', '1942-03-24');
INSERT INTO PetOwner VALUES ('Darrelle', 'Colette', 'cdurrandkp@google.ca', 'vos73Mh', '2005-05-08', 'false', 'F', '1 Di Loreto Court', '1945-07-02');
INSERT INTO PetOwner VALUES ('Kimberly', 'Felicdad', 'fcrossmankq@youtube.com', '2zjmEyV9', '2018-12-03', 'true', 'F', '052 Hazelcrest Parkway', '1956-07-20');
INSERT INTO PetOwner VALUES ('Madelina', 'Margarita', 'momarakr@photobucket.com', 'qTUr2Vr', '2002-06-25', 'true', 'F', '7 Scoville Point', '2015-07-07');
INSERT INTO PetOwner VALUES ('Donetta', 'Glad', 'ghaganks@simplemachines.org', 'at5AYpYX', '2010-09-22', 'false', 'F', '6 Cherokee Lane', '1999-06-28');
INSERT INTO PetOwner VALUES ('Hollyanne', 'Saloma', 'slebrunkt@squidoo.com', 'toIJjH', '2007-04-08', 'false', 'F', '562 Bayside Parkway', '1959-12-09');
INSERT INTO PetOwner VALUES ('Reube', 'Giffard', 'gdunmoreku@hp.com', 'YLYChP62VGC', '2001-08-05', 'false', 'M', '61 Oxford Park', '1936-12-13');
INSERT INTO PetOwner VALUES ('Viola', 'Walliw', 'wdrewrykv@list-manage.com', 'p5iyxexDa', '2007-11-24', 'true', 'F', '23 Esker Way', '2005-08-24');
INSERT INTO PetOwner VALUES ('Dyann', 'Ninetta', 'nchaisekw@aboutads.info', 'jnNkPw0uF', '2004-10-26', 'false', 'F', '31928 Doe Crossing Point', '1985-05-22');
INSERT INTO PetOwner VALUES ('Beatrice', 'Trixi', 'tmaingotkx@engadget.com', 'dn1M7I3w0', '2013-07-16', 'true', 'F', '6 Michigan Street', '1991-10-20');
INSERT INTO PetOwner VALUES ('Reg', 'Arthur', 'amooreedky@bing.com', 'ixSH00ePw', '2003-04-29', 'true', 'M', '20 Kensington Plaza', '1993-06-26');
INSERT INTO PetOwner VALUES ('Ferguson', 'Amory', 'acrewskz@cdc.gov', '0BtZYvAl', '2014-11-29', 'true', 'M', '6 Canary Place', '1933-08-28');
INSERT INTO PetOwner VALUES ('Fey', 'Paula', 'pcrushl0@walmart.com', 'kmaR9fd2tIR', '2019-01-04', 'false', 'F', '278 Shelley Way', '1972-12-09');
INSERT INTO PetOwner VALUES ('Franz', 'Sigmund', 'sokilll1@nba.com', 'vuj65vnn', '2019-04-27', 'false', 'M', '2 Northwestern Terrace', '1978-03-30');
INSERT INTO PetOwner VALUES ('Elwin', 'Bale', 'bschwiesol2@usnews.com', 'zoIBGlNsV6f', '2015-02-26', 'true', 'M', '78 Rieder Junction', '1936-12-22');
INSERT INTO PetOwner VALUES ('Gilberte', 'Gretta', 'gformanl3@goo.gl', 'kX8Fh054', '2016-09-07', 'false', 'F', '59 Montana Terrace', '2009-10-31');
INSERT INTO PetOwner VALUES ('Manny', 'Upton', 'uhannondl4@hatena.ne.jp', 'hNcPVDMQBLC', '2014-12-11', 'false', 'M', '922 Schurz Parkway', '1965-05-27');
INSERT INTO PetOwner VALUES ('Viole', 'Ardine', 'ahonatschl5@bloglovin.com', 'uWSxBfK', '2004-02-07', 'false', 'F', '61 Jay Street', '1956-09-27');
INSERT INTO PetOwner VALUES ('Kristine', 'Janie', 'jhirschmannl6@twitter.com', '68ldH19', '2020-07-15', 'true', 'F', '787 Mendota Point', '1943-03-08');
INSERT INTO PetOwner VALUES ('Seumas', 'Johny', 'jdymentl7@ed.gov', 'ZdPRHvhb', '2017-05-05', 'true', 'M', '2 Tony Park', '1980-02-25');
INSERT INTO PetOwner VALUES ('Silvana', 'Adi', 'astennardl8@vistaprint.com', 'NW6g1V0XydHl', '2006-11-30', 'false', 'F', '9232 Colorado Street', '2010-04-02');
INSERT INTO PetOwner VALUES ('Dolores', 'Tammara', 'tmonellel9@istockphoto.com', 'PDqkfPZ', '2009-10-30', 'false', 'F', '86 Nobel Parkway', '1952-11-11');
INSERT INTO PetOwner VALUES ('Granny', 'Everard', 'ebazochela@tiny.cc', 'tnxgAO5N', '2014-11-23', 'true', 'M', '056 Rigney Place', '1953-06-13');
INSERT INTO PetOwner VALUES ('Udall', 'Noland', 'njointlb@prweb.com', 'Qb3we4N', '2016-10-17', 'true', 'M', '88 Old Shore Crossing', '1976-02-06');
INSERT INTO PetOwner VALUES ('Charin', 'Marylou', 'mbissilllc@ucoz.com', 'UEBQhdqvv', '2001-11-18', 'false', 'F', '19 Dayton Pass', '1982-07-01');
INSERT INTO PetOwner VALUES ('Aldridge', 'Sheffield', 'swederellld@friendfeed.com', 'Eny7wLfoUd', '2016-05-25', 'true', 'M', '5 Sage Court', '2014-05-03');
INSERT INTO PetOwner VALUES ('Frasco', 'Massimiliano', 'mwinslowle@simplemachines.org', 'PkaeD86ll', '2001-11-22', 'false', 'M', '729 Stephen Avenue', '1990-02-22');
INSERT INTO PetOwner VALUES ('Krissie', 'Adelind', 'aboulterlg@blogspot.com', 'EzRtUG', '2002-05-20', 'false', 'F', '93912 Buhler Center', '1973-12-28');
INSERT INTO PetOwner VALUES ('Glennis', 'Annis', 'amcmylorlh@npr.org', 'tutzqE6lFuua', '2010-05-27', 'true', 'F', '15 Farwell Drive', '1990-12-25');
INSERT INTO PetOwner VALUES ('Fran', 'Adaline', 'ablodgettsli@columbia.edu', 'eX6k7Lpfq0fk', '2007-06-06', 'false', 'F', '87 Morrow Hill', '1940-01-17');
INSERT INTO PetOwner VALUES ('Casar', 'Rolland', 'rcoumbelj@yelp.com', '8Kay2I', '2015-08-25', 'false', 'M', '974 Express Trail', '2012-04-02');
INSERT INTO PetOwner VALUES ('Rickard', 'Danie', 'dstairlk@sciencedaily.com', 'Ews7TcyJlO', '2004-11-21', 'false', 'M', '2748 Bluejay Avenue', '2013-12-14');
INSERT INTO PetOwner VALUES ('Annis', 'Kalina', 'kcrutll@spiegel.de', 'LghIzStYhKKT', '2010-09-22', 'false', 'F', '41508 Dovetail Street', '1976-12-21');
INSERT INTO PetOwner VALUES ('Clari', 'Bethena', 'bpiscottilm@prlog.org', '9TVJS6WnBkEi', '2010-08-23', 'false', 'F', '893 Lindbergh Crossing', '1971-11-06');
INSERT INTO PetOwner VALUES ('Nesta', 'Adrienne', 'afulopln@ebay.co.uk', 'LDx4Bstmt6I1', '2006-01-20', 'true', 'F', '045 Waxwing Plaza', '1972-08-08');
INSERT INTO PetOwner VALUES ('Ruby', 'Marcelo', 'mdelgadillolo@t.co', 'bfJY0QQXp', '2008-01-16', 'true', 'M', '49 Hanover Alley', '1935-05-31');
INSERT INTO PetOwner VALUES ('Gideon', 'Gram', 'gjosovitzlp@acquirethisname.com', 'LNm6v6NRO', '2017-07-04', 'false', 'M', '6138 Moland Park', '1943-06-24');
INSERT INTO PetOwner VALUES ('Dav', 'Tristam', 'ttwelvetreeslq@instagram.com', '4m92yK', '2004-08-22', 'true', 'M', '83498 Lerdahl Place', '2015-03-28');
INSERT INTO PetOwner VALUES ('Rakel', 'Nell', 'nangelllr@jalbum.net', 'nNO2oDqztW', '2005-03-19', 'true', 'F', '4168 International Hill', '1972-10-20');
INSERT INTO PetOwner VALUES ('Tiertza', 'Ellen', 'ewiltshirels@ocn.ne.jp', 'w0IgLIE1Vy', '2011-05-13', 'true', 'F', '9 Kennedy Park', '1986-01-04');
INSERT INTO PetOwner VALUES ('Constancy', 'Wynne', 'wwarrierlt@wufoo.com', '8xRIzy9', '2013-06-27', 'false', 'F', '3200 Mesta Alley', '1932-03-02');
INSERT INTO PetOwner VALUES ('Earl', 'Otho', 'osabathierlu@miitbeian.gov.cn', 'mHnwYeXcfxs', '2020-09-19', 'false', 'M', '8 Sachs Place', '1947-01-26');
INSERT INTO PetOwner VALUES ('Romola', 'Eyde', 'ewimplv@mapquest.com', '8Dccp0h3', '2003-06-19', 'true', 'F', '8 Cascade Way', '2005-01-15');
INSERT INTO PetOwner VALUES ('Valaria', 'Em', 'eboskelllx@paginegialle.it', '6gQGGLsxE', '2017-08-20', 'true', 'F', '764 Dwight Plaza', '1997-12-08');
INSERT INTO PetOwner VALUES ('Tammie', 'Marcello', 'mlorriely@addtoany.com', 'j5QTr6', '2004-05-13', 'true', 'M', '6 Lerdahl Place', '2015-02-20');
INSERT INTO PetOwner VALUES ('Drusilla', 'Merle', 'mplattlz@msu.edu', 'FhVtiEbL1', '2007-03-11', 'false', 'F', '7 Ronald Regan Alley', '2006-03-24');
INSERT INTO PetOwner VALUES ('Olwen', 'Kamillah', 'kdymottm0@aboutads.info', 'sOiaIs8GB', '2013-05-12', 'true', 'F', '28 Dayton Lane', '1976-09-18');
INSERT INTO PetOwner VALUES ('Delmore', 'Ossie', 'omaidlowm1@jalbum.net', 'wCvaw2ENuP2d', '2004-02-25', 'false', 'M', '6012 Butterfield Plaza', '2013-04-05');
INSERT INTO PetOwner VALUES ('Leigha', 'Donnamarie', 'dgilmorem2@prweb.com', 'cOjhj3iDETP', '2011-03-13', 'false', 'F', '33865 Surrey Circle', '2010-04-01');
INSERT INTO PetOwner VALUES ('Lanny', 'Lebbie', 'lruzicm3@samsung.com', 'f6lWmaC', '2012-11-13', 'true', 'F', '2 Graceland Drive', '1934-02-25');
INSERT INTO PetOwner VALUES ('Miltie', 'Stevy', 'sblunnm4@over-blog.com', 'w8M4gLJXh', '2013-07-26', 'false', 'M', '4596 Darwin Junction', '2005-11-02');
INSERT INTO PetOwner VALUES ('Hedda', 'Waly', 'wlecountm5@prlog.org', 'p8XgHjRu', '2017-04-21', 'false', 'F', '25 Huxley Hill', '1944-01-18');
INSERT INTO PetOwner VALUES ('Perkin', 'Hillery', 'hdaenenm7@phoca.cz', 'BOlM6KE', '2010-08-25', 'false', 'M', '9855 Rusk Way', '2011-09-12');
INSERT INTO PetOwner VALUES ('Moyra', 'Sally', 'slearnedm8@lulu.com', 'qWnGPk', '2012-10-10', 'true', 'F', '40 Buena Vista Parkway', '1986-05-29');
INSERT INTO PetOwner VALUES ('Vilhelmina', 'Mikaela', 'mbagwellm9@infoseek.co.jp', 'VlVlLQNX7Z', '2002-02-06', 'false', 'F', '0051 Washington Way', '1987-09-18');
INSERT INTO PetOwner VALUES ('Blane', 'Kendrick', 'kduquesnayma@dell.com', 'b9xFXibzdP', '2000-11-07', 'false', 'M', '5633 Lawn Road', '1962-06-06');
INSERT INTO PetOwner VALUES ('Kissee', 'Sibeal', 'ssheepymb@unc.edu', 'XfmaBOj', '2014-11-20', 'true', 'F', '33 Macpherson Junction', '1963-05-28');
INSERT INTO PetOwner VALUES ('Scotty', 'Leopold', 'lbussettimc@mayoclinic.com', 'MBle1atLO8', '2017-09-08', 'true', 'M', '59613 Lillian Center', '2010-10-01');
INSERT INTO PetOwner VALUES ('Kippy', 'Odo', 'ocandelinmd@github.io', 'DB1SlqqWg', '2002-09-16', 'false', 'M', '2 Sutteridge Plaza', '1987-04-10');
INSERT INTO PetOwner VALUES ('Lane', 'Jean', 'jbolusme@nps.gov', 'VCLKIC', '2004-06-27', 'true', 'F', '09 Bay Way', '1956-05-31');
INSERT INTO PetOwner VALUES ('Sher', 'Deny', 'dpenrittmf@webs.com', 'PueCk2eEI1xs', '2001-04-15', 'true', 'F', '5 Del Mar Park', '1943-03-02');
INSERT INTO PetOwner VALUES ('Kristofer', 'Ashlin', 'abartosekmg@gov.uk', '6QVVIG17EMu', '2019-03-19', 'true', 'M', '8165 Manufacturers Center', '1996-03-04');
INSERT INTO PetOwner VALUES ('Ky', 'Gifford', 'gweblinmh@geocities.com', '8wR44gVcDo', '2012-01-15', 'true', 'M', '41 Grover Park', '1938-05-03');
INSERT INTO PetOwner VALUES ('Monroe', 'Witty', 'wyakobovitzmi@ted.com', '2giN8TinT', '2013-03-12', 'true', 'M', '33 Fordem Way', '1966-09-09');
INSERT INTO PetOwner VALUES ('Alden', 'Edlin', 'edanilevichmj@uiuc.edu', 'JCU1VoSVhL6', '2013-04-23', 'false', 'M', '87816 Spohn Junction', '1971-04-07');
INSERT INTO PetOwner VALUES ('Peria', 'Felicle', 'ftignermk@fastcompany.com', 'Z9E0l4aqdljK', '2020-02-22', 'false', 'F', '28 Butterfield Plaza', '1989-01-26');
INSERT INTO PetOwner VALUES ('Karlik', 'Dylan', 'dmargeramml@prnewswire.com', 'vzx016b37', '2020-01-24', 'false', 'M', '919 Hollow Ridge Lane', '1952-12-10');
INSERT INTO PetOwner VALUES ('Robina', 'Leone', 'lpericomm@phpbb.com', 'vyMdZTa7brd', '2018-11-09', 'true', 'F', '4 Roth Circle', '1979-11-18');
INSERT INTO PetOwner VALUES ('Jobye', 'Gratia', 'gcreasemn@live.com', 'gQb09cmm', '2011-06-19', 'false', 'F', '00036 Quincy Lane', '2012-11-21');
INSERT INTO PetOwner VALUES ('Jillian', 'Trix', 'tmclellanmo@wunderground.com', 'zUZFaKNHp', '2018-04-30', 'false', 'F', '42550 Ronald Regan Street', '2018-08-23');
INSERT INTO PetOwner VALUES ('Tiena', 'Ivette', 'ineavesmp@qq.com', 'ZZEKXMJ2', '2012-08-22', 'false', 'F', '9462 Sheridan Circle', '1967-07-27');
INSERT INTO PetOwner VALUES ('Indira', 'Wrennie', 'wrunnettmq@xing.com', 'VZyLQeuBheLr', '2017-05-21', 'true', 'F', '75241 Derek Point', '2001-08-23');
INSERT INTO PetOwner VALUES ('Lotti', 'Arline', 'adreakinmr@a8.net', 'L5E3lJLaRmo', '2008-12-11', 'true', 'F', '106 Ramsey Crossing', '1944-04-23');
INSERT INTO PetOwner VALUES ('Marita', 'Fiorenze', 'fmcgrahms@webs.com', 'bdN5D6q12', '2009-01-17', 'true', 'F', '54 Crownhardt Point', '1953-06-30');
INSERT INTO PetOwner VALUES ('Sam', 'Cindelyn', 'celcocksmt@apple.com', 't8TxXH2', '2006-01-17', 'false', 'F', '0282 Morningstar Place', '1998-03-17');
INSERT INTO PetOwner VALUES ('Rockwell', 'Jourdain', 'jgawnmu@de.vu', 'ogrG52DbswS', '2017-09-20', 'true', 'M', '4 Shasta Road', '1981-03-08');
INSERT INTO PetOwner VALUES ('Donnie', 'Piper', 'ptymmv@blinklist.com', '5iGunT', '2017-07-29', 'false', 'F', '0 Elgar Trail', '2015-02-13');
INSERT INTO PetOwner VALUES ('Chaddie', 'Zolly', 'zreyemw@icio.us', 'BuxDraOm', '2004-05-14', 'false', 'M', '9775 Marquette Lane', '1987-03-18');
INSERT INTO PetOwner VALUES ('Chrissy', 'Morley', 'mpolkinghornemy@whitehouse.gov', 'UXUYvOpT', '2019-10-31', 'false', 'M', '85 Swallow Place', '2005-06-11');
INSERT INTO PetOwner VALUES ('Christalle', 'Goldarina', 'gpolgreenmz@phpbb.com', 'B6AcsUYL', '2020-07-07', 'true', 'F', '18 Ohio Way', '2013-08-27');
INSERT INTO PetOwner VALUES ('Joshia', 'Farlie', 'fregon0@newyorker.com', 'OARvhlDaAX3R', '2016-03-18', 'false', 'M', '5062 Bunker Hill Crossing', '1982-04-22');
INSERT INTO PetOwner VALUES ('Bobbe', 'Jaquelin', 'jibeln1@usda.gov', '4RihBx99hhv3', '2018-10-28', 'true', 'F', '1772 Rusk Drive', '2006-08-02');
INSERT INTO PetOwner VALUES ('Dud', 'Nial', 'nweatherleyn2@parallels.com', 'ytqS1gKJ', '2018-04-16', 'true', 'M', '55274 Pleasure Alley', '1973-10-11');
INSERT INTO PetOwner VALUES ('Loydie', 'Sanson', 'sfranklingn3@squidoo.com', 'eIGcX3nYOMp', '2003-09-07', 'true', 'M', '0686 Cherokee Hill', '2005-10-06');
INSERT INTO PetOwner VALUES ('Mayor', 'Gene', 'gvonhindenburgn4@prlog.org', 'kJD47HUCCxb', '2002-07-07', 'false', 'M', '61078 Schmedeman Trail', '1948-09-29');
INSERT INTO PetOwner VALUES ('Trumann', 'Titos', 'trommen5@engadget.com', 'p8D9sf88D', '2000-12-09', 'false', 'M', '2 Westridge Crossing', '1932-09-11');
INSERT INTO PetOwner VALUES ('Zorah', 'Tersina', 'thannahn6@behance.net', 'l6iKfH36eJlY', '2001-08-20', 'false', 'F', '48448 Old Gate Hill', '1990-05-07');
INSERT INTO PetOwner VALUES ('Olivero', 'Ansell', 'abodkern7@sfgate.com', 'vgq01G', '2010-03-26', 'false', 'M', '6 Oakridge Plaza', '1946-03-17');
INSERT INTO PetOwner VALUES ('Etan', 'Jamison', 'jpiochn8@artisteer.com', '6LDCyOevdz', '2003-05-26', 'false', 'M', '7016 Sheridan Park', '1939-05-14');
INSERT INTO PetOwner VALUES ('Ase', 'Tyler', 'tmcdirmidn9@weibo.com', 'xyAbKKgc', '2014-01-26', 'false', 'M', '1605 Cottonwood Alley', '1951-06-30');
INSERT INTO PetOwner VALUES ('Elihu', 'Claiborne', 'cmataninna@techcrunch.com', 'iLIS3B', '2007-05-14', 'false', 'M', '8843 Arkansas Place', '1994-03-25');
INSERT INTO PetOwner VALUES ('Deb', 'Perle', 'phamshawnb@chron.com', '4dTd9QgbNj', '2016-12-06', 'false', 'F', '11757 Mallard Place', '1974-09-12');
INSERT INTO PetOwner VALUES ('Natalya', 'Letizia', 'lscrewtonnc@intel.com', 'tq2ID2pE4J', '2013-06-28', 'true', 'F', '9947 Pepper Wood Point', '1953-12-20');
INSERT INTO PetOwner VALUES ('Jakie', 'Renard', 'rcasesnd@squidoo.com', 'mcFBHjZ', '2005-11-29', 'false', 'M', '6 Graceland Parkway', '1956-08-09');
INSERT INTO PetOwner VALUES ('Herman', 'Rutter', 'rleathleyne@dropbox.com', 't3mGXWfjdX', '2009-10-09', 'false', 'M', '0668 Monterey Avenue', '1990-10-22');
INSERT INTO PetOwner VALUES ('Rutherford', 'Boris', 'brimenf@facebook.com', 'OGtdAQYRnwZ', '2018-12-10', 'false', 'M', '80 Fisk Junction', '2001-01-20');
INSERT INTO PetOwner VALUES ('Woodrow', 'Laughton', 'lsargintng@livejournal.com', 'v3cZa20IkN8', '2014-07-22', 'true', 'M', '4613 6th Lane', '2001-12-08');
INSERT INTO PetOwner VALUES ('Durant', 'Gordy', 'gtattoonh@usda.gov', 'lZGnP5qf6e', '2006-03-20', 'true', 'M', '303 Linden Hill', '1953-03-19');
INSERT INTO PetOwner VALUES ('Chariot', 'Huntington', 'hbloodni@nydailynews.com', 'ASVSA2lTlZyF', '2015-01-24', 'false', 'M', '2 High Crossing Drive', '1991-10-25');
INSERT INTO PetOwner VALUES ('Mick', 'Brenden', 'blovittnj@reverbnation.com', 'mKJ6MI4y', '2017-12-19', 'false', 'M', '901 Sunbrook Hill', '2011-02-20');
INSERT INTO PetOwner VALUES ('Klarrisa', 'Veda', 'vbignellnk@purevolume.com', 'C6GIFhMAI', '2014-05-15', 'false', 'F', '02 Upham Pass', '1992-09-18');
INSERT INTO PetOwner VALUES ('Joice', 'Quinn', 'qvickerynl@godaddy.com', 'VPH8Xxm', '2001-05-06', 'true', 'F', '974 Bonner Drive', '1964-10-07');
INSERT INTO PetOwner VALUES ('Weston', 'Tobin', 'toscanlonnm@hatena.ne.jp', 'IErTpPLi', '2009-12-27', 'true', 'M', '5 Bultman Place', '1980-12-25');
INSERT INTO PetOwner VALUES ('Thatcher', 'Symon', 'sanfussonn@japanpost.jp', 'aDVOl2h1e4qb', '2018-06-16', 'false', 'M', '18 Annamark Circle', '2019-04-30');
INSERT INTO PetOwner VALUES ('Haskel', 'Keary', 'khebbsno@prlog.org', 'zHVyIK', '2008-11-11', 'false', 'M', '4 Caliangt Alley', '2012-08-24');
INSERT INTO PetOwner VALUES ('Oliviero', 'Keefer', 'kharbisonnp@bloomberg.com', '1jOcUZZk1', '2013-09-12', 'false', 'M', '828 Vernon Alley', '1988-12-26');
INSERT INTO PetOwner VALUES ('Cora', 'Cami', 'cgrentnq@merriam-webster.com', '48b7vI3', '2010-07-16', 'true', 'F', '340 Hovde Terrace', '1980-02-26');
INSERT INTO PetOwner VALUES ('Davie', 'Morie', 'mhaggarthns@xing.com', 'yNU3Dx', '2017-04-23', 'true', 'M', '752 Grasskamp Point', '2000-02-02');
INSERT INTO PetOwner VALUES ('Berton', 'Marco', 'mmusgravent@goo.ne.jp', 'btN6eqgfF', '2010-02-10', 'false', 'M', '541 Main Road', '1964-03-26');
INSERT INTO PetOwner VALUES ('Franciska', 'Diannne', 'deytelnu@weibo.com', 'rP97VDruV', '2006-01-17', 'false', 'F', '8 Pennsylvania Hill', '1968-09-11');
INSERT INTO PetOwner VALUES ('Pascale', 'Harlin', 'hcarmonv@quantcast.com', '579tnV', '2010-01-22', 'true', 'M', '95 Sheridan Lane', '2017-05-17');
INSERT INTO PetOwner VALUES ('Glori', 'Bert', 'bbraunfeldnw@blogs.com', 'G6LYo9q', '2010-08-18', 'true', 'F', '2069 Pine View Avenue', '2015-12-24');
INSERT INTO PetOwner VALUES ('Bat', 'Nollie', 'nkeighlynx@ucsd.edu', 'ZcHptdmZc', '2008-04-02', 'true', 'M', '4 Myrtle Court', '1995-02-24');
INSERT INTO PetOwner VALUES ('Andromache', 'Eden', 'ecaseborneny@eventbrite.com', 'poRvI18A', '2013-06-12', 'false', 'F', '13 Northport Trail', '1961-01-12');
INSERT INTO PetOwner VALUES ('Kelly', 'Far', 'farundelnz@cocolog-nifty.com', 'vLWTRp', '2008-06-12', 'false', 'M', '91 Loftsgordon Drive', '1948-09-06');
INSERT INTO PetOwner VALUES ('Godard', 'Vin', 'vhurtono0@mtv.com', 'UTlLUGW84w', '2013-10-13', 'true', 'M', '61629 Emmet Crossing', '1973-10-30');
INSERT INTO PetOwner VALUES ('Carma', 'Kati', 'kharrhyo1@prnewswire.com', 'aXjqbdlw8y', '2014-09-11', 'false', 'F', '06537 Kensington Junction', '1974-11-30');
INSERT INTO PetOwner VALUES ('Mellisent', 'Dosi', 'dkilbeeo2@sphinn.com', 'CW6I3d7jKz', '2008-03-30', 'true', 'F', '03003 Summit Lane', '2014-03-20');
INSERT INTO PetOwner VALUES ('Winny', 'Barty', 'bpeacockeo3@google.co.jp', 'y0WT0DIm11o', '2004-07-31', 'false', 'M', '618 Dorton Road', '1973-09-09');
INSERT INTO PetOwner VALUES ('Serene', 'Joni', 'jbaudouo4@odnoklassniki.ru', 'vFwJr9Lz4EAt', '2004-01-10', 'true', 'F', '2419 Bluejay Street', '1942-02-08');
INSERT INTO PetOwner VALUES ('Liza', 'Clarette', 'casselo5@printfriendly.com', 'K1BPhK', '2015-09-01', 'true', 'F', '389 Cardinal Street', '1974-10-14');
INSERT INTO PetOwner VALUES ('Aubrette', 'Coretta', 'cgluyuso6@theglobeandmail.com', 'vwBEWutmB3Or', '2020-02-14', 'false', 'F', '15 Stoughton Way', '1969-02-10');
INSERT INTO PetOwner VALUES ('Silas', 'Jarred', 'jvericko7@google.com.hk', 'jkwRzEaDUN72', '2014-04-07', 'false', 'M', '63 Anhalt Center', '1971-11-17');
INSERT INTO PetOwner VALUES ('Anastassia', 'Faith', 'fjaymeo8@privacy.gov.au', 'mvGCk1', '2016-01-29', 'true', 'F', '0 Old Gate Street', '1972-09-16');
INSERT INTO PetOwner VALUES ('Dredi', 'Ingrid', 'iytero9@w3.org', 'd06AWrh', '2002-12-10', 'true', 'F', '4043 Reinke Alley', '1963-01-04');
INSERT INTO PetOwner VALUES ('Kean', 'Rodrick', 'rkezourecoa@dell.com', 'Ccdmzr', '2007-04-09', 'false', 'M', '3 Ramsey Road', '1956-10-17');
INSERT INTO PetOwner VALUES ('Kasey', 'Nicoline', 'ncallicottob@prweb.com', 'hoExbmTbks', '2012-10-07', 'true', 'F', '9 Larry Alley', '2006-07-23');
INSERT INTO PetOwner VALUES ('Myrtle', 'Gilberta', 'gconfordoc@gravatar.com', 'VXgOuGHPswW', '2009-01-14', 'true', 'F', '906 Kedzie Road', '1963-05-27');
INSERT INTO PetOwner VALUES ('Baxie', 'Terry', 'thillborneod@digg.com', 'HePhCTJ', '2012-05-29', 'false', 'M', '9 Kipling Drive', '2006-02-05');
INSERT INTO PetOwner VALUES ('Yulma', 'Raddy', 'rmcelaneoe@bloglines.com', 'XLrqyyOJ', '2002-03-17', 'false', 'M', '5781 Forest Run Circle', '1973-02-07');
INSERT INTO PetOwner VALUES ('Maurie', 'Devlin', 'ddowtyof@php.net', 'S2wemqxim', '2012-10-28', 'false', 'M', '1407 Walton Circle', '1932-12-05');
INSERT INTO PetOwner VALUES ('Bibbie', 'Arielle', 'adeeganog@gmpg.org', 'wpHBMy', '2009-10-07', 'false', 'F', '71091 Grasskamp Plaza', '1975-03-29');
INSERT INTO PetOwner VALUES ('Albie', 'Johny', 'jmoralasoh@acquirethisname.com', 'siKWXpulPOX', '2009-10-27', 'true', 'M', '28826 Kipling Plaza', '1953-01-19');
INSERT INTO PetOwner VALUES ('Kerrin', 'Vivianne', 'vmccarrickoi@is.gd', 'LNbej035f', '2018-09-08', 'true', 'F', '58657 Nelson Parkway', '2004-02-14');
INSERT INTO PetOwner VALUES ('Gustavus', 'Ulysses', 'ubenwelloj@usatoday.com', 'qSUKDoANlEv', '2011-10-10', 'true', 'M', '36 Kipling Avenue', '1986-08-13');
INSERT INTO PetOwner VALUES ('Fedora', 'Korie', 'kbuckberryok@smugmug.com', 'Uzj5vc', '2018-09-14', 'true', 'F', '08041 Mcbride Crossing', '1990-03-20');
INSERT INTO PetOwner VALUES ('Garrik', 'Sammy', 'sharmanol@youku.com', 'WeYd504lDbbF', '2001-10-13', 'true', 'M', '72 Loftsgordon Plaza', '2012-01-29');
INSERT INTO PetOwner VALUES ('Brade', 'Kelvin', 'kbolzenom@de.vu', 'SFQ1Kjoka2', '2006-08-17', 'true', 'M', '552 Lillian Terrace', '1955-01-14');
INSERT INTO PetOwner VALUES ('Tuesday', 'Helenelizabeth', 'hvasilievon@npr.org', '7LfadqO4', '2017-10-14', 'false', 'F', '917 Luster Pass', '2014-04-28');
INSERT INTO PetOwner VALUES ('Reamonn', 'Adlai', 'asquirreloo@marketwatch.com', 'iRdlAspl', '2017-09-27', 'true', 'M', '7 Sauthoff Street', '2014-08-02');
INSERT INTO PetOwner VALUES ('Cheston', 'Fleming', 'fswynop@seesaa.net', 'ca46eWp5E', '2009-10-12', 'false', 'M', '42392 Rieder Parkway', '1985-02-07');
INSERT INTO PetOwner VALUES ('Adrianne', 'Marcile', 'mclawsleyoq@netscape.com', 'UWHc6Z', '2018-07-11', 'true', 'F', '553 Welch Point', '1971-11-27');
INSERT INTO PetOwner VALUES ('Hartwell', 'Jarrod', 'jbeaconsallor@census.gov', 'BVZdUuY7yDt', '2003-05-03', 'false', 'M', '56 Nelson Street', '1934-12-15');
INSERT INTO PetOwner VALUES ('Klaus', 'Chet', 'cromneyos@wikia.com', 'o42Yt0', '2010-04-24', 'true', 'M', '9402 Hanson Alley', '1968-12-08');
INSERT INTO PetOwner VALUES ('Patrizio', 'Georas', 'gleyborneot@europa.eu', 'zGph0woP', '2008-05-16', 'true', 'M', '59 Lighthouse Bay Place', '1953-05-19');
INSERT INTO PetOwner VALUES ('Alister', 'Sidnee', 'sclewloweou@ucoz.com', 'rbkZFgWTx7iR', '2004-12-10', 'true', 'M', '2 Susan Parkway', '2018-04-18');
INSERT INTO PetOwner VALUES ('Clint', 'Say', 'swestmorelandov@alibaba.com', 'L3MpAYw', '2009-02-28', 'false', 'M', '75656 Nelson Point', '1932-01-09');
INSERT INTO PetOwner VALUES ('Jemimah', 'Tierney', 'tstickfordow@webeden.co.uk', 'FX8ngbg2', '2001-11-12', 'true', 'F', '0 Sullivan Crossing', '1955-05-26');
INSERT INTO PetOwner VALUES ('Charlton', 'Lawton', 'lgonox@desdev.cn', 'eJ7Pa5Nmnu', '2009-06-02', 'false', 'M', '4112 Bartelt Lane', '1983-11-20');
INSERT INTO PetOwner VALUES ('Geno', 'Dex', 'dgamlynoy@flavors.me', 'cHtJHmDe', '2014-01-08', 'true', 'M', '5346 Norway Maple Parkway', '1947-07-25');
INSERT INTO PetOwner VALUES ('Briggs', 'Avigdor', 'aduckfieldoz@microsoft.com', 'f2VRcc', '2012-07-11', 'false', 'M', '625 Oakridge Avenue', '1955-12-20');
INSERT INTO PetOwner VALUES ('Fraze', 'Ingmar', 'islarkp1@tamu.edu', 'ZmGcsF43lPFS', '2016-06-09', 'false', 'M', '684 School Drive', '1969-08-09');
INSERT INTO PetOwner VALUES ('Doroteya', 'Hortensia', 'hhaskinsp2@economist.com', 'DDjSgsT', '2019-04-03', 'false', 'F', '0284 Pearson Avenue', '1969-11-24');
INSERT INTO PetOwner VALUES ('Veriee', 'Tamarah', 'thedylstonep3@merriam-webster.com', 'H4WcikDgKB', '2020-01-12', 'true', 'F', '26170 Bashford Court', '2019-05-16');
INSERT INTO PetOwner VALUES ('Kevin', 'Gaby', 'gtackp4@360.cn', '3DUnKwc', '2007-12-22', 'true', 'M', '1 Tony Avenue', '1963-05-31');
INSERT INTO PetOwner VALUES ('Binni', 'Marjory', 'mtomichp5@wikipedia.org', 'fbBU9t8wVx', '2009-08-01', 'false', 'F', '50547 Duke Point', '1933-04-08');
INSERT INTO PetOwner VALUES ('Rawley', 'Tremain', 'tpicfordp6@topsy.com', '6ca6XTy83TfM', '2016-08-13', 'true', 'M', '02 Independence Crossing', '1960-11-22');
INSERT INTO PetOwner VALUES ('Carin', 'Astrix', 'anorthropp7@cafepress.com', 'CV13PU0i', '2002-04-07', 'false', 'F', '0 Ruskin Terrace', '1971-05-19');
INSERT INTO PetOwner VALUES ('Dyana', 'Tommy', 'tbogacep8@gnu.org', 'rM9STFjL', '2005-04-02', 'true', 'F', '23612 Rigney Point', '2002-02-20');
INSERT INTO PetOwner VALUES ('Falkner', 'Rex', 'rfownesp9@homestead.com', 'RHeaVCi0qF', '2016-04-13', 'false', 'M', '6 Buena Vista Plaza', '1954-03-05');
INSERT INTO PetOwner VALUES ('Randell', 'Tucker', 'tsisspa@xrea.com', 'vLHLmux', '2010-07-24', 'false', 'M', '6 3rd Plaza', '1966-10-22');
INSERT INTO PetOwner VALUES ('Ardyth', 'Madelaine', 'mfrewerpb@abc.net.au', 'THvyJFufAtE', '2020-04-08', 'false', 'F', '81959 Merrick Trail', '1936-04-02');
INSERT INTO PetOwner VALUES ('Faber', 'Willy', 'wleupoldtpc@photobucket.com', 'x07doe9', '2002-07-25', 'false', 'M', '865 Badeau Lane', '2009-07-05');
INSERT INTO PetOwner VALUES ('Meta', 'Rachelle', 'rdowbakinpd@taobao.com', 'eJCLvl0U', '2015-03-06', 'true', 'F', '11 Schlimgen Parkway', '1973-01-16');
INSERT INTO PetOwner VALUES ('Phedra', 'Shandra', 'sbulluckpe@narod.ru', '3b7t1QygP', '2015-02-19', 'true', 'F', '21009 Tony Alley', '1971-10-16');
INSERT INTO PetOwner VALUES ('Benoit', 'George', 'gnickelspf@seesaa.net', 'NE93sY3giqC', '2001-03-28', 'true', 'M', '3126 Canary Point', '2020-04-18');
INSERT INTO PetOwner VALUES ('Andres', 'Carrol', 'cabramovpg@yelp.com', 'wqCDX8m', '2005-09-25', 'true', 'M', '8 Hansons Point', '2009-12-12');
INSERT INTO PetOwner VALUES ('Andras', 'Monro', 'mevettsph@cmu.edu', 'szcYGo1IlS', '2017-05-09', 'false', 'M', '06182 Old Gate Park', '2003-10-21');
INSERT INTO PetOwner VALUES ('Fraser', 'Arman', 'aanchorpi@wufoo.com', 'LRLBMoa', '2016-02-20', 'true', 'M', '52 Pepper Wood Crossing', '1968-06-19');
INSERT INTO PetOwner VALUES ('Hyacinthe', 'Janine', 'jsturtepj@xrea.com', 'e7bIdam8J', '2006-08-21', 'false', 'F', '11 Sheridan Plaza', '2010-06-06');
INSERT INTO PetOwner VALUES ('Laurie', 'Zane', 'zduthypk@bing.com', 'Zo7XRr9oH', '2020-05-16', 'false', 'M', '7918 Fordem Trail', '1960-08-26');
INSERT INTO PetOwner VALUES ('Rowen', 'Lyon', 'lmcgreaypl@goo.gl', 'ESwvdCNn5S0C', '2014-08-28', 'false', 'M', '0248 Claremont Center', '2004-02-07');
INSERT INTO PetOwner VALUES ('Hurlee', 'Beniamino', 'bgimsonpm@yolasite.com', 'rC6usjlVW', '2018-03-14', 'false', 'M', '4840 Lukken Court', '1990-11-20');
INSERT INTO PetOwner VALUES ('Hagan', 'Carce', 'cmassonpn@nba.com', 'aBL2Pow', '2000-11-05', 'true', 'M', '1207 Old Gate Street', '1993-03-22');
INSERT INTO PetOwner VALUES ('Mireille', 'Mignon', 'mwilsteadpp@rakuten.co.jp', 'Ctxd8aXOeUN5', '2015-09-18', 'false', 'F', '8 Karstens Place', '1961-09-24');
INSERT INTO PetOwner VALUES ('Aldo', 'Ole', 'oalessandonepr@studiopress.com', '2kMS9PS', '2003-11-12', 'false', 'M', '11215 3rd Plaza', '1941-10-11');
INSERT INTO PetOwner VALUES ('Mattheus', 'Claudianus', 'clissandrept@vistaprint.com', 'U09u651yCOTN', '2018-09-15', 'false', 'M', '31 Nelson Center', '1941-05-10');
INSERT INTO PetOwner VALUES ('Marven', 'Erl', 'emacrannellpu@1688.com', 'DQjae19', '2008-08-28', 'true', 'M', '5766 Dawn Plaza', '1941-08-22');
INSERT INTO PetOwner VALUES ('Derby', 'Roi', 'rhinschepv@g.co', '3Ps9eDqX3', '2001-01-05', 'true', 'M', '805 Londonderry Crossing', '2013-05-20');
INSERT INTO PetOwner VALUES ('Hertha', 'Minnnie', 'mphonixpw@ycombinator.com', 'yNhKtt', '2014-11-10', 'false', 'F', '81239 Mcbride Hill', '1955-04-21');
INSERT INTO PetOwner VALUES ('Leshia', 'Perl', 'prickettspx@reference.com', 'JAvMMN9nEd', '2007-06-13', 'false', 'F', '9 Cascade Circle', '1935-06-27');
INSERT INTO PetOwner VALUES ('Terri', 'Laurence', 'lwithinshawpy@1und1.de', 'KxgJbjK', '2002-12-19', 'false', 'M', '96827 Rigney Alley', '2004-11-02');
INSERT INTO PetOwner VALUES ('Rickie', 'Carlos', 'cpietrowiczpz@symantec.com', 'jDJBj89IcXi', '2002-10-18', 'true', 'M', '70409 Muir Trail', '1968-03-22');
INSERT INTO PetOwner VALUES ('Marylou', 'Tildie', 'tsabbinsq0@booking.com', 'Skarbtb', '2011-02-14', 'true', 'F', '6413 Old Shore Road', '1943-10-21');
INSERT INTO PetOwner VALUES ('Kellen', 'Von', 'vraspelq1@wix.com', 'p6CqA2nh', '2001-10-28', 'true', 'M', '6924 Iowa Road', '1969-04-22');
INSERT INTO PetOwner VALUES ('Sonja', 'Ethelyn', 'edigiorgioq2@state.gov', '8QOoOfNia', '2010-08-13', 'false', 'F', '7844 Iowa Park', '1940-01-02');
INSERT INTO PetOwner VALUES ('Ichabod', 'Royce', 'rbulstrodeq4@cmu.edu', 'z0agKNMKAUj', '2019-11-23', 'false', 'M', '90 Messerschmidt Parkway', '1992-09-27');
INSERT INTO PetOwner VALUES ('Antonie', 'Bren', 'bbooiq5@google.ru', 'lAq67Xch', '2009-06-05', 'true', 'F', '10 Rockefeller Crossing', '1959-07-09');
INSERT INTO PetOwner VALUES ('Glynis', 'Dorotea', 'dpetzoltq7@nhs.uk', 'GSwWzgF3yji', '2004-10-14', 'true', 'F', '00658 Ludington Center', '1990-01-12');
INSERT INTO PetOwner VALUES ('Gratiana', 'Ardenia', 'apatersonq8@blogger.com', 'bU3hYR3dHK3v', '2010-05-24', 'false', 'F', '1532 Killdeer Alley', '1960-03-31');
INSERT INTO PetOwner VALUES ('Marnie', 'Lorenza', 'lgrillsq9@ft.com', 'dL7HBOZE', '2018-12-18', 'false', 'F', '16309 Norway Maple Way', '2011-07-23');
INSERT INTO PetOwner VALUES ('Gisella', 'Jessie', 'jrobbertqa@deviantart.com', 'ECqNDLWh', '2007-04-10', 'true', 'F', '8990 Northridge Plaza', '1946-07-17');
INSERT INTO PetOwner VALUES ('Quinlan', 'Deane', 'dfawcusqb@slashdot.org', 'VnaYGAirLX', '2009-02-20', 'false', 'M', '095 Hauk Drive', '1931-02-15');
INSERT INTO PetOwner VALUES ('Stevena', 'Caralie', 'cconachyqc@usatoday.com', 'K7TWcJB', '2005-12-15', 'false', 'F', '42 Forster Terrace', '1983-09-02');
INSERT INTO PetOwner VALUES ('Ashil', 'Carlene', 'cwillmoreqd@usda.gov', 'Ji1dlf', '2005-11-11', 'true', 'F', '46 Hanson Terrace', '1974-03-10');
INSERT INTO PetOwner VALUES ('Kilian', 'Vincenty', 'vmozziqf@census.gov', 'oPXF5eyF2', '2013-03-09', 'false', 'M', '6 Dryden Point', '1963-05-31');
INSERT INTO PetOwner VALUES ('Shauna', 'Modestia', 'mmenlowqh@bloglines.com', 'lNGkAn', '2003-03-16', 'true', 'F', '772 Anderson Junction', '1989-05-18');
INSERT INTO PetOwner VALUES ('Mommy', 'Valaree', 'vflayqi@mlb.com', 'JVnLpTEmFd', '2019-12-17', 'false', 'F', '3 Welch Lane', '1995-05-17');
INSERT INTO PetOwner VALUES ('Raynor', 'Walt', 'wdaughtonqj@wiley.com', 'Vb4Y4FnBdVJ', '2005-09-24', 'true', 'M', '9 Basil Court', '1987-05-23');
INSERT INTO PetOwner VALUES ('Koenraad', 'Giuseppe', 'gblancoweqk@edublogs.org', 'MecRcIwN8iVy', '2003-11-28', 'false', 'M', '96 Meadow Valley Parkway', '1973-12-15');
INSERT INTO PetOwner VALUES ('Archy', 'Wittie', 'wrickeardql@shinystat.com', 'nWI780zv', '2008-07-08', 'false', 'M', '179 Marquette Avenue', '1996-10-06');
INSERT INTO PetOwner VALUES ('Modestia', 'Kandy', 'knoseworthyqm@behance.net', 'LvWt9f6u', '2010-07-19', 'false', 'F', '60546 Schmedeman Way', '2000-09-29');
INSERT INTO PetOwner VALUES ('Raoul', 'Dominique', 'ddareyqn@buzzfeed.com', '4K6Mrrp', '2005-02-05', 'false', 'M', '28 Hintze Crossing', '1978-04-19');
INSERT INTO PetOwner VALUES ('Conan', 'Graeme', 'gkennsleyqo@addtoany.com', 'i7g2Ef', '2008-08-08', 'true', 'M', '78413 Main Trail', '1963-01-04');
INSERT INTO PetOwner VALUES ('Belvia', 'Bess', 'bandragqp@prweb.com', 'KWkkQFQ', '2020-08-02', 'true', 'F', '34617 Sage Drive', '1986-08-06');
INSERT INTO PetOwner VALUES ('Shanan', 'Marve', 'mselewayqr@elpais.com', 'UHMyxk', '2007-11-24', 'true', 'M', '60 Summer Ridge Lane', '1934-04-17');
INSERT INTO PetOwner VALUES ('Jamaal', 'Barr', 'bedmonsonqt@comcast.net', 'AcfrqiLZJ', '2001-09-23', 'false', 'M', '4 Almo Place', '1987-09-17');
INSERT INTO PetOwner VALUES ('Roxanne', 'Gwenny', 'gattlequ@narod.ru', 'uhgSFhBLL1o', '2003-12-19', 'true', 'F', '83271 Esch Street', '1980-06-12');
INSERT INTO PetOwner VALUES ('Delcine', 'Aloise', 'apockettqv@techcrunch.com', 'zmaPgpOZ6CR', '2007-01-15', 'true', 'F', '930 Mesta Road', '2010-04-28');
INSERT INTO PetOwner VALUES ('Trevar', 'Gerome', 'gruttqw@ed.gov', 'Ezun4C9', '2010-09-11', 'false', 'M', '06 Acker Center', '1994-04-01');
INSERT INTO PetOwner VALUES ('Ertha', 'Fan', 'ftattamqx@surveymonkey.com', 'jX2DX3Jv4Baf', '2004-07-19', 'true', 'F', '05 Jana Pass', '1992-01-09');
INSERT INTO PetOwner VALUES ('Jodie', 'Amalie', 'aludwikiewiczqy@wikimedia.org', 'qJaS2icThPdi', '2014-07-27', 'false', 'F', '32771 Norway Maple Road', '1953-07-17');
INSERT INTO PetOwner VALUES ('Nealson', 'Callean', 'cdurekqz@youku.com', 'qBypZczTuQjV', '2006-12-31', 'true', 'M', '00597 Loftsgordon Avenue', '1943-07-01');
INSERT INTO PetOwner VALUES ('Traver', 'Emmanuel', 'egrashar1@webs.com', 'CY3WSo4qfS5', '2018-03-09', 'true', 'M', '25 Summer Ridge Terrace', '1945-03-01');
INSERT INTO PetOwner VALUES ('Nicolai', 'Hort', 'hdanilishinr2@plala.or.jp', 'Sg7IgHBr9ImX', '2019-12-16', 'false', 'M', '0 Park Meadow Junction', '1956-07-10');
INSERT INTO PetOwner VALUES ('Richardo', 'Temple', 'tsockellr3@macromedia.com', '8XPPw2E', '2016-05-20', 'true', 'M', '91 Cherokee Alley', '1990-05-08');
INSERT INTO PetOwner VALUES ('Angus', 'Jasun', 'jgiffonr4@blinklist.com', 'T8aoEhTIFxl', '2000-12-15', 'true', 'M', '688 Portage Terrace', '1996-06-27');
INSERT INTO PetOwner VALUES ('Fitzgerald', 'Vachel', 'vrudallr6@census.gov', 'ikftPMvC', '2011-09-26', 'true', 'M', '1 Warrior Way', '1957-07-29');
INSERT INTO PetOwner VALUES ('Port', 'De witt', 'dlawdenr7@japanpost.jp', 'mfveV6YKL', '2020-04-11', 'false', 'M', '1748 Armistice Terrace', '2012-04-14');
INSERT INTO PetOwner VALUES ('Evelin', 'Jephthah', 'jdebler9@timesonline.co.uk', 'BzRRmL', '2001-07-06', 'true', 'M', '33113 Oriole Hill', '2019-10-11');
INSERT INTO PetOwner VALUES ('Alex', 'Munmro', 'metchinghamra@hexun.com', 'uLazN8HlN2', '2001-02-24', 'false', 'M', '8 Hagan Avenue', '2020-08-14');
INSERT INTO PetOwner VALUES ('Bonnee', 'Joly', 'jharbinsonrb@smugmug.com', 'T95Wg46VaqS', '2020-05-30', 'false', 'F', '5 Transport Point', '1963-10-09');
INSERT INTO PetOwner VALUES ('Bartolomeo', 'Zacharia', 'zharbertrc@bbc.co.uk', 'VJMf6YgJVehF', '2009-02-26', 'true', 'M', '121 Roxbury Way', '2001-08-11');
INSERT INTO PetOwner VALUES ('Ermengarde', 'Emelita', 'eannellrd@cornell.edu', 'RYsMkuYoOz5x', '2012-02-11', 'false', 'F', '59 Graceland Lane', '1964-09-28');
INSERT INTO PetOwner VALUES ('Cleopatra', 'Gay', 'gcargenvenre@pen.io', '9lghE4fG', '2006-12-04', 'false', 'F', '65175 Kenwood Court', '1953-12-03');
INSERT INTO PetOwner VALUES ('Sullivan', 'Rube', 'rklainrf@shinystat.com', 'TzgJsfb', '2008-09-04', 'false', 'M', '57 Porter Hill', '2009-12-18');
INSERT INTO PetOwner VALUES ('Aguistin', 'Tommie', 'tocanavanrg@wsj.com', '1pHVX4F3Je', '2013-11-16', 'false', 'M', '5325 Swallow Crossing', '1970-12-23');
INSERT INTO PetOwner VALUES ('Amie', 'Tootsie', 'tpentecostrh@goodreads.com', 'JD1FjmW8t0u', '2007-03-24', 'false', 'F', '41835 Arrowood Alley', '1936-11-17');
INSERT INTO PetOwner VALUES ('Bret', 'Luis', 'lbroadbearri@ucoz.ru', 'B36jzGX', '2008-12-17', 'true', 'M', '58453 Maple Wood Road', '1950-03-09');
INSERT INTO PetOwner VALUES ('Salim', 'Monti', 'mjobbingsrj@yolasite.com', 'j9afgADyCiv', '2003-05-28', 'false', 'M', '240 Mendota Crossing', '2012-09-27');
INSERT INTO PetOwner VALUES ('Akim', 'Desmund', 'dstapyltonrl@addthis.com', 'LRz9AUtz8BN3', '2007-06-19', 'false', 'M', '6 Hanson Pass', '2012-04-03');
INSERT INTO PetOwner VALUES ('Russell', 'Lewiss', 'lsmerdonrm@paypal.com', 'QQ7HBgkaQRz', '2010-01-03', 'false', 'M', '42 Dixon Park', '2020-05-03');
INSERT INTO PetOwner VALUES ('Malina', 'Berry', 'bbletsorrn@theatlantic.com', 'X3SUBxyx', '2014-05-09', 'false', 'F', '2081 Prairie Rose Avenue', '1982-07-20');
INSERT INTO PetOwner VALUES ('Tanner', 'Garald', 'ggullifantro@youku.com', '9XFM3fzuWxU9', '2015-02-25', 'false', 'M', '8 Fallview Place', '2004-11-14');
INSERT INTO PetOwner VALUES ('Zachariah', 'Quillan', 'qrevittrp@biglobe.ne.jp', 'c4R94n0e', '2008-04-17', 'false', 'M', '210 Hovde Pass', '1974-07-13');
INSERT INTO PetOwner VALUES ('Cliff', 'Garry', 'gbrixeyrq@cocolog-nifty.com', 'aYCHIg', '2001-08-01', 'false', 'M', '9 Main Pass', '1956-12-05');
INSERT INTO PetOwner VALUES ('Jannelle', 'Oona', 'ogillivrierr@tuttocitta.it', 'evhqAPBWsyup', '2006-05-29', 'true', 'F', '3 Namekagon Crossing', '1978-03-24');
INSERT INTO PetOwner VALUES ('Anissa', 'Brittani', 'btomley0@businesswire.com', 'udUbhX9Aebd', '2018-06-16', 'false', 'F', '1 Forster Way', '2002-10-18');
INSERT INTO PetOwner VALUES ('Arlena', 'Olympe', 'omattack1@msu.edu', 'raMt8P', '2016-07-23', 'true', 'F', '53 Havey Drive', '2010-04-27');
INSERT INTO PetOwner VALUES ('Elvira', 'Dorry', 'dwybourne2@wordpress.org', 'Rb8ZWwnFYvoz', '2015-07-25', 'false', 'F', '39 Linden Court', '1994-04-02');
INSERT INTO PetOwner VALUES ('Weidar', 'Arte', 'alawton3@sogou.com', 'k8y3QrHeK', '2007-02-03', 'true', 'M', '7 Bonner Pass', '1988-07-26');
INSERT INTO PetOwner VALUES ('Carver', 'Bryanty', 'bmullenger4@reddit.com', 'Eg56Cnhpe', '2011-05-24', 'false', 'M', '15376 4th Circle', '1991-02-01');
INSERT INTO PetOwner VALUES ('Mickey', 'Emlyn', 'epalmar5@quantcast.com', 'otu3yAjc', '2014-11-29', 'true', 'M', '4504 Crownhardt Trail', '1988-01-22');
INSERT INTO PetOwner VALUES ('Yance', 'Joshia', 'jredihough6@slashdot.org', 'nsJEe2I', '2020-08-18', 'true', 'M', '66083 Fairfield Way', '1958-08-05');
INSERT INTO PetOwner VALUES ('Forrester', 'Garvy', 'gfarnhill7@tinypic.com', 'WBdx8um', '2002-11-26', 'true', 'M', '0581 Thackeray Point', '1985-12-15');
INSERT INTO PetOwner VALUES ('Vivianne', 'Beverlee', 'bcristofor8@opensource.org', 'sXGzRRJ8kn5', '2016-07-18', 'true', 'F', '50037 Melvin Street', '2003-10-23');
INSERT INTO PetOwner VALUES ('Sayers', 'Abran', 'amosleya@soundcloud.com', 's3vO6e', '2008-06-13', 'false', 'M', '145 Oakridge Drive', '1936-06-11');
INSERT INTO PetOwner VALUES ('Chloris', 'Daisi', 'dwoakesb@fotki.com', 'r1EL5nIQHGAu', '2004-06-24', 'true', 'F', '43939 Paget Crossing', '1982-07-25');
INSERT INTO PetOwner VALUES ('Elizabeth', 'Cris', 'cpiersec@tripadvisor.com', 'dGljW5S', '2008-01-08', 'true', 'F', '39324 Mifflin Junction', '1993-07-10');
INSERT INTO PetOwner VALUES ('Craggy', 'Melvin', 'mstelfoxe@jugem.jp', 'Qhpgotfh', '2008-12-08', 'true', 'M', '469 Morningstar Pass', '1996-09-14');
INSERT INTO PetOwner VALUES ('Freddi', 'Rubetta', 'rwallbridgeg@uol.com.br', 'xUkxQSFz', '2014-07-31', 'false', 'F', '13 Towne Crossing', '1969-08-28');
INSERT INTO PetOwner VALUES ('Odelia', 'Dinnie', 'dmotherwellh@howstuffworks.com', 'WSrWWh', '2014-12-17', 'true', 'F', '1 Sutteridge Court', '1941-10-09');
INSERT INTO PetOwner VALUES ('Lemuel', 'Hilliard', 'hleathej@imdb.com', 'kQ1qbNFZFIV3', '2001-04-27', 'false', 'M', '672 Dixon Plaza', '1952-12-05');
INSERT INTO PetOwner VALUES ('Burgess', 'Obadiah', 'oschalll@ted.com', '0HdU0wXc2', '2016-04-10', 'true', 'M', '81066 Pearson Hill', '1977-04-04');
INSERT INTO PetOwner VALUES ('Cornall', 'Puff', 'pderwinm@slashdot.org', 'qYgZXnz', '2009-12-07', 'true', 'M', '060 Evergreen Drive', '2000-01-07');
INSERT INTO PetOwner VALUES ('La verne', 'Sheba', 'stremellingn@ibm.com', 'ErA3MFm3i', '2018-07-14', 'false', 'F', '02945 Washington Terrace', '2014-08-08');
INSERT INTO PetOwner VALUES ('Cynthy', 'Edeline', 'emegaheyo@va.gov', '2yNOo9d', '2014-03-30', 'true', 'F', '856 Johnson Point', '1936-03-08');
INSERT INTO PetOwner VALUES ('Roarke', 'Derril', 'droughp@amazon.de', '886LANA', '2012-11-29', 'true', 'M', '7008 Bluejay Avenue', '2011-12-17');
INSERT INTO PetOwner VALUES ('Norean', 'Jessamyn', 'jivanuschkaq@yale.edu', 'MWBLUvx4', '2013-02-03', 'false', 'F', '2104 Jackson Court', '1953-05-29');
INSERT INTO PetOwner VALUES ('Felita', 'Harriett', 'hhaberchamr@nydailynews.com', 'WmEtQ9', '2006-02-10', 'true', 'F', '1 Basil Center', '1952-04-21');
INSERT INTO PetOwner VALUES ('Ferdinande', 'Tamiko', 'taleksankins@quantcast.com', '401X5E2Ui', '2001-11-08', 'true', 'F', '914 Cascade Alley', '1943-01-08');
INSERT INTO PetOwner VALUES ('Corry', 'Avrit', 'abuffyt@hostgator.com', 'I9iRP2', '2013-11-25', 'false', 'F', '9727 Sullivan Avenue', '1983-09-13');
INSERT INTO PetOwner VALUES ('Carter', 'Adolph', 'aculkinv@globo.com', 'u3BItFxHDC', '2002-04-27', 'false', 'M', '117 Karstens Alley', '1993-04-17');
INSERT INTO PetOwner VALUES ('Reid', 'Colet', 'ccollinettew@tripod.com', 'Auldg6yXC', '2007-02-18', 'true', 'M', '461 Southridge Point', '1994-12-16');
INSERT INTO PetOwner VALUES ('Nils', 'Marlin', 'mcornhillx@marketwatch.com', 'pTlNhOl7vFem', '2007-05-05', 'true', 'M', '4 Grasskamp Circle', '1990-08-03');
INSERT INTO PetOwner VALUES ('Kelli', 'Sharia', 'sburridgey@purevolume.com', 'F9LHNniA', '2004-02-10', 'false', 'F', '7514 Erie Trail', '2014-04-25');
INSERT INTO PetOwner VALUES ('Daisy', 'Tessi', 'thoblez@amazonaws.com', 'RzulO70a0kP', '2020-01-07', 'true', 'F', '01 Glacier Hill Way', '1977-05-16');
INSERT INTO PetOwner VALUES ('Laverne', 'Merissa', 'mburke10@t.co', 'UBdTQ0F', '2009-03-07', 'false', 'F', '76207 Fair Oaks Crossing', '1976-09-19');
INSERT INTO PetOwner VALUES ('Amalle', 'Doralynne', 'dhovert11@xinhuanet.com', '6whZ6AWCz', '2012-01-15', 'true', 'F', '56 Trailsway Plaza', '2010-10-03');
INSERT INTO PetOwner VALUES ('Avril', 'Almira', 'adrummond12@ucla.edu', 'VVq1ROKW', '2011-01-10', 'true', 'F', '1562 Delaware Terrace', '1980-06-05');
INSERT INTO PetOwner VALUES ('Tades', 'Cosimo', 'cwhiteman13@oaic.gov.au', 'ID6ItPt0O7', '2001-03-13', 'true', 'M', '6560 Vahlen Way', '1994-05-06');
INSERT INTO PetOwner VALUES ('Hall', 'Chickie', 'cmcmarquis14@flickr.com', 'c0lKNjT', '2020-01-21', 'true', 'M', '4 Dunning Place', '1966-11-13');
INSERT INTO PetOwner VALUES ('Dinny', 'Mellie', 'marnaut15@addtoany.com', 'd0a5IeR', '2010-12-26', 'true', 'F', '7626 Mccormick Avenue', '1958-11-28');
INSERT INTO PetOwner VALUES ('Farrell', 'Penny', 'pheimes16@amazonaws.com', '4pYhMJt', '2014-08-11', 'false', 'M', '989 Harper Hill', '1998-05-05');
INSERT INTO PetOwner VALUES ('Brunhilde', 'Nelie', 'ngamwell17@ycombinator.com', '6UYTPK', '2018-04-27', 'false', 'F', '73547 Mandrake Way', '1964-06-26');
INSERT INTO PetOwner VALUES ('Vincent', 'Shurwood', 'sbeaglehole18@posterous.com', '4QqS1K', '2014-08-15', 'true', 'M', '69351 Briar Crest Lane', '1963-03-16');
INSERT INTO PetOwner VALUES ('Holly', 'Chip', 'cdimbleby19@ca.gov', '9JA9aS6Q', '2004-01-04', 'true', 'M', '61 Bowman Circle', '1956-09-04');
INSERT INTO PetOwner VALUES ('Patrica', 'Wally', 'wbaline1a@sun.com', '7B8mQsRI', '2012-06-03', 'false', 'F', '88 Delaware Hill', '1994-07-22');

/*----------------------------------------------------*/
/* PetCategory 100*/
INSERT INTO PetCategory VALUES ('Koi', '70.00');
INSERT INTO PetCategory VALUES ('Rodents', '90.00');
INSERT INTO PetCategory VALUES ('Ferrets', '110.00');
INSERT INTO PetCategory VALUES ('Mosquitofish', '120.00');
INSERT INTO PetCategory VALUES ('Columbines', '180.00');
INSERT INTO PetCategory VALUES ('Chinchillas', '60.00');
INSERT INTO PetCategory VALUES ('Guppy', '100.00');
INSERT INTO PetCategory VALUES ('Sheep', '90.00');
INSERT INTO PetCategory VALUES ('Fowl', '140.00');
INSERT INTO PetCategory VALUES ('Goldfish', '50.00');
INSERT INTO PetCategory VALUES ('Rabbits', '130.00');
INSERT INTO PetCategory VALUES ('Alpacas', '60.00');
INSERT INTO PetCategory VALUES ('Goats', '60.00');
INSERT INTO PetCategory VALUES ('Barb', '160.00');
INSERT INTO PetCategory VALUES ('Cattle', '90.00');
INSERT INTO PetCategory VALUES ('Dogs', '70.00');
INSERT INTO PetCategory VALUES ('Hedgehogs', '160.00');
INSERT INTO PetCategory VALUES ('Horses', '120.00');
INSERT INTO PetCategory VALUES ('Cats', '150.00');
INSERT INTO PetCategory VALUES ('Pigs', '70.00');

/*----------------------------------------------------*/
/* CareTaker 500*/
INSERT INTO CareTaker VALUES ('Clemens', '0');
INSERT INTO CareTaker VALUES ('Georgetta', '0');
INSERT INTO CareTaker VALUES ('Tabor', '0');
INSERT INTO CareTaker VALUES ('Fern', '0');
INSERT INTO CareTaker VALUES ('Abby', '0');
INSERT INTO CareTaker VALUES ('Aron', '0');
INSERT INTO CareTaker VALUES ('Clementius', '0');
INSERT INTO CareTaker VALUES ('Gare', '0');
INSERT INTO CareTaker VALUES ('Cybil', '0');
INSERT INTO CareTaker VALUES ('Brendon', '0');
INSERT INTO CareTaker VALUES ('Petr', '0');
INSERT INTO CareTaker VALUES ('Frederica', '0');
INSERT INTO CareTaker VALUES ('Gwenni', '0');
INSERT INTO CareTaker VALUES ('Wood', '0');
INSERT INTO CareTaker VALUES ('Von', '0');
INSERT INTO CareTaker VALUES ('Eba', '0');
INSERT INTO CareTaker VALUES ('Avram', '0');
INSERT INTO CareTaker VALUES ('Nilson', '0');
INSERT INTO CareTaker VALUES ('Gran', '0');
INSERT INTO CareTaker VALUES ('Janos', '0');
INSERT INTO CareTaker VALUES ('Dion', '0');
INSERT INTO CareTaker VALUES ('Dalton', '0');
INSERT INTO CareTaker VALUES ('Eilis', '0');
INSERT INTO CareTaker VALUES ('Earle', '0');
INSERT INTO CareTaker VALUES ('Irma', '0');
INSERT INTO CareTaker VALUES ('Joseito', '0');
INSERT INTO CareTaker VALUES ('Frannie', '0');
INSERT INTO CareTaker VALUES ('Steven', '0');
INSERT INTO CareTaker VALUES ('Donia', '0');
INSERT INTO CareTaker VALUES ('Grant', '0');
INSERT INTO CareTaker VALUES ('Pepe', '0');
INSERT INTO CareTaker VALUES ('Elsa', '0');
INSERT INTO CareTaker VALUES ('Shelagh', '0');
INSERT INTO CareTaker VALUES ('Mahmoud', '0');
INSERT INTO CareTaker VALUES ('Bastian', '0');
INSERT INTO CareTaker VALUES ('Erin', '0');
INSERT INTO CareTaker VALUES ('Cordelia', '0');
INSERT INTO CareTaker VALUES ('Herbert', '0');
INSERT INTO CareTaker VALUES ('Hedy', '0');
INSERT INTO CareTaker VALUES ('Raven', '0');
INSERT INTO CareTaker VALUES ('Berenice', '0');
INSERT INTO CareTaker VALUES ('Giorgia', '0');
INSERT INTO CareTaker VALUES ('Courtenay', '0');
INSERT INTO CareTaker VALUES ('Lulita', '0');
INSERT INTO CareTaker VALUES ('Nataniel', '0');
INSERT INTO CareTaker VALUES ('Hayley', '0');
INSERT INTO CareTaker VALUES ('Maisey', '0');
INSERT INTO CareTaker VALUES ('Ruthanne', '0');
INSERT INTO CareTaker VALUES ('Giuditta', '0');
INSERT INTO CareTaker VALUES ('Garth', '0');
INSERT INTO CareTaker VALUES ('Dierdre', '0');
INSERT INTO CareTaker VALUES ('Clyde', '0');
INSERT INTO CareTaker VALUES ('Hymie', '0');
INSERT INTO CareTaker VALUES ('Timmie', '0');
INSERT INTO CareTaker VALUES ('Eulalie', '0');
INSERT INTO CareTaker VALUES ('Spike', '0');
INSERT INTO CareTaker VALUES ('Conant', '0');
INSERT INTO CareTaker VALUES ('Walker', '0');
INSERT INTO CareTaker VALUES ('Norby', '0');
INSERT INTO CareTaker VALUES ('Debbi', '0');
INSERT INTO CareTaker VALUES ('Uta', '0');
INSERT INTO CareTaker VALUES ('Briano', '0');
INSERT INTO CareTaker VALUES ('Flem', '0');
INSERT INTO CareTaker VALUES ('Dalt', '0');
INSERT INTO CareTaker VALUES ('Lorilyn', '0');
INSERT INTO CareTaker VALUES ('Tremaine', '0');
INSERT INTO CareTaker VALUES ('Dalston', '0');
INSERT INTO CareTaker VALUES ('Janina', '0');
INSERT INTO CareTaker VALUES ('Baron', '0');
INSERT INTO CareTaker VALUES ('Cirilo', '0');
INSERT INTO CareTaker VALUES ('Rafaello', '0');
INSERT INTO CareTaker VALUES ('Rossy', '0');
INSERT INTO CareTaker VALUES ('Allyson', '0');
INSERT INTO CareTaker VALUES ('Burke', '0');
INSERT INTO CareTaker VALUES ('Townie', '0');
INSERT INTO CareTaker VALUES ('Bax', '0');
INSERT INTO CareTaker VALUES ('Arel', '0');
INSERT INTO CareTaker VALUES ('Antoni', '0');
INSERT INTO CareTaker VALUES ('Clementine', '0');
INSERT INTO CareTaker VALUES ('Bernardina', '0');
INSERT INTO CareTaker VALUES ('Cass', '0');
INSERT INTO CareTaker VALUES ('Dacie', '0');
INSERT INTO CareTaker VALUES ('Bernetta', '0');
INSERT INTO CareTaker VALUES ('Ursola', '0');
INSERT INTO CareTaker VALUES ('Melvyn', '0');
INSERT INTO CareTaker VALUES ('Cary', '0');
INSERT INTO CareTaker VALUES ('Ellswerth', '0');
INSERT INTO CareTaker VALUES ('Binnie', '0');
INSERT INTO CareTaker VALUES ('Danie', '0');
INSERT INTO CareTaker VALUES ('Malcolm', '0');
INSERT INTO CareTaker VALUES ('Napoleon', '0');
INSERT INTO CareTaker VALUES ('Phineas', '0');
INSERT INTO CareTaker VALUES ('Farah', '0');
INSERT INTO CareTaker VALUES ('Loise', '0');
INSERT INTO CareTaker VALUES ('Tore', '0');
INSERT INTO CareTaker VALUES ('Fayre', '0');
INSERT INTO CareTaker VALUES ('Kylie', '0');
INSERT INTO CareTaker VALUES ('Natty', '0');
INSERT INTO CareTaker VALUES ('Cece', '0');
INSERT INTO CareTaker VALUES ('Kali', '0');
INSERT INTO CareTaker VALUES ('Waverley', '0');
INSERT INTO CareTaker VALUES ('Diena', '0');
INSERT INTO CareTaker VALUES ('Hunter', '0');
INSERT INTO CareTaker VALUES ('Darnell', '0');
INSERT INTO CareTaker VALUES ('Idaline', '0');
INSERT INTO CareTaker VALUES ('Kimberley', '0');
INSERT INTO CareTaker VALUES ('Jacobo', '0');
INSERT INTO CareTaker VALUES ('Lyle', '0');
INSERT INTO CareTaker VALUES ('Clea', '0');
INSERT INTO CareTaker VALUES ('Ram', '0');
INSERT INTO CareTaker VALUES ('Kordula', '0');
INSERT INTO CareTaker VALUES ('Bell', '0');
INSERT INTO CareTaker VALUES ('Freeland', '0');
INSERT INTO CareTaker VALUES ('Roderigo', '0');
INSERT INTO CareTaker VALUES ('Genny', '0');
INSERT INTO CareTaker VALUES ('Jordanna', '0');
INSERT INTO CareTaker VALUES ('Algernon', '0');
INSERT INTO CareTaker VALUES ('Tedd', '0');
INSERT INTO CareTaker VALUES ('Palm', '0');
INSERT INTO CareTaker VALUES ('Lorita', '0');
INSERT INTO CareTaker VALUES ('Hedwiga', '0');
INSERT INTO CareTaker VALUES ('Markos', '0');
INSERT INTO CareTaker VALUES ('Jerri', '0');
INSERT INTO CareTaker VALUES ('El', '0');
INSERT INTO CareTaker VALUES ('Konstance', '0');
INSERT INTO CareTaker VALUES ('Allin', '0');
INSERT INTO CareTaker VALUES ('Allen', '0');
INSERT INTO CareTaker VALUES ('Etienne', '0');
INSERT INTO CareTaker VALUES ('Adrian', '0');
INSERT INTO CareTaker VALUES ('Valencia', '0');
INSERT INTO CareTaker VALUES ('Waylen', '0');
INSERT INTO CareTaker VALUES ('Jere', '0');
INSERT INTO CareTaker VALUES ('Ephrayim', '0');
INSERT INTO CareTaker VALUES ('Barr', '0');
INSERT INTO CareTaker VALUES ('Issy', '0');
INSERT INTO CareTaker VALUES ('Christie', '0');
INSERT INTO CareTaker VALUES ('Cris', '0');
INSERT INTO CareTaker VALUES ('Lars', '0');
INSERT INTO CareTaker VALUES ('Salvador', '0');
INSERT INTO CareTaker VALUES ('Monika', '0');
INSERT INTO CareTaker VALUES ('Goldy', '0');
INSERT INTO CareTaker VALUES ('Lorry', '0');
INSERT INTO CareTaker VALUES ('Hannah', '0');
INSERT INTO CareTaker VALUES ('Adrienne', '0');
INSERT INTO CareTaker VALUES ('Bron', '0');
INSERT INTO CareTaker VALUES ('Kirby', '0');
INSERT INTO CareTaker VALUES ('Jonis', '0');
INSERT INTO CareTaker VALUES ('Oralie', '0');
INSERT INTO CareTaker VALUES ('Josefa', '0');
INSERT INTO CareTaker VALUES ('Adoree', '0');
INSERT INTO CareTaker VALUES ('Packston', '0');
INSERT INTO CareTaker VALUES ('Kane', '0');
INSERT INTO CareTaker VALUES ('Wade', '0');
INSERT INTO CareTaker VALUES ('Mae', '0');
INSERT INTO CareTaker VALUES ('Sigfrid', '0');
INSERT INTO CareTaker VALUES ('Rhys', '0');
INSERT INTO CareTaker VALUES ('Morris', '0');
INSERT INTO CareTaker VALUES ('Essy', '0');
INSERT INTO CareTaker VALUES ('Aubree', '0');
INSERT INTO CareTaker VALUES ('Sharia', '0');
INSERT INTO CareTaker VALUES ('Taber', '0');
INSERT INTO CareTaker VALUES ('Mortie', '0');
INSERT INTO CareTaker VALUES ('Amery', '0');
INSERT INTO CareTaker VALUES ('Reinwald', '0');
INSERT INTO CareTaker VALUES ('Gianna', '0');
INSERT INTO CareTaker VALUES ('Laurence', '0');
INSERT INTO CareTaker VALUES ('Alfie', '0');
INSERT INTO CareTaker VALUES ('Willow', '0');
INSERT INTO CareTaker VALUES ('Edythe', '0');
INSERT INTO CareTaker VALUES ('Micaela', '0');
INSERT INTO CareTaker VALUES ('Jemmie', '0');
INSERT INTO CareTaker VALUES ('Jami', '0');
INSERT INTO CareTaker VALUES ('Morly', '0');
INSERT INTO CareTaker VALUES ('Jacquetta', '0');
INSERT INTO CareTaker VALUES ('Freddy', '0');
INSERT INTO CareTaker VALUES ('Pauly', '0');
INSERT INTO CareTaker VALUES ('Bradan', '0');
INSERT INTO CareTaker VALUES ('Ansley', '0');
INSERT INTO CareTaker VALUES ('Celka', '0');
INSERT INTO CareTaker VALUES ('Alfredo', '0');
INSERT INTO CareTaker VALUES ('Rabbi', '0');
INSERT INTO CareTaker VALUES ('Maureene', '0');
INSERT INTO CareTaker VALUES ('Odo', '0');
INSERT INTO CareTaker VALUES ('Harlen', '0');
INSERT INTO CareTaker VALUES ('Maurizio', '0');
INSERT INTO CareTaker VALUES ('Dre', '0');
INSERT INTO CareTaker VALUES ('Emalee', '0');
INSERT INTO CareTaker VALUES ('Korey', '0');
INSERT INTO CareTaker VALUES ('Kay', '0');
INSERT INTO CareTaker VALUES ('Chrysa', '0');
INSERT INTO CareTaker VALUES ('Rudie', '0');
INSERT INTO CareTaker VALUES ('Mignon', '0');
INSERT INTO CareTaker VALUES ('Jemie', '0');
INSERT INTO CareTaker VALUES ('Ricki', '0');
INSERT INTO CareTaker VALUES ('Kinsley', '0');
INSERT INTO CareTaker VALUES ('Rodolfo', '0');
INSERT INTO CareTaker VALUES ('Marion', '0');
INSERT INTO CareTaker VALUES ('Zacharia', '0');
INSERT INTO CareTaker VALUES ('Ike', '0');
INSERT INTO CareTaker VALUES ('Tallia', '0');
INSERT INTO CareTaker VALUES ('Catharine', '0');
INSERT INTO CareTaker VALUES ('Inessa', '0');
INSERT INTO CareTaker VALUES ('Vittoria', '0');
INSERT INTO CareTaker VALUES ('Wilhelm', '0');
INSERT INTO CareTaker VALUES ('Abbott', '0');
INSERT INTO CareTaker VALUES ('Ofelia', '0');
INSERT INTO CareTaker VALUES ('Merrill', '0');
INSERT INTO CareTaker VALUES ('Paulina', '0');
INSERT INTO CareTaker VALUES ('Krissy', '0');
INSERT INTO CareTaker VALUES ('Judah', '0');
INSERT INTO CareTaker VALUES ('Sandra', '0');
INSERT INTO CareTaker VALUES ('Loralyn', '0');
INSERT INTO CareTaker VALUES ('Tyler', '0');
INSERT INTO CareTaker VALUES ('Suzi', '0');
INSERT INTO CareTaker VALUES ('Mychal', '0');
INSERT INTO CareTaker VALUES ('Eddie', '0');
INSERT INTO CareTaker VALUES ('Hilarius', '0');
INSERT INTO CareTaker VALUES ('Caroljean', '0');
INSERT INTO CareTaker VALUES ('Ernesta', '0');
INSERT INTO CareTaker VALUES ('Clarita', '0');
INSERT INTO CareTaker VALUES ('Loree', '0');
INSERT INTO CareTaker VALUES ('Fonz', '0');
INSERT INTO CareTaker VALUES ('Duff', '0');
INSERT INTO CareTaker VALUES ('Carlynne', '0');
INSERT INTO CareTaker VALUES ('Dina', '0');
INSERT INTO CareTaker VALUES ('Rasla', '0');
INSERT INTO CareTaker VALUES ('Nickie', '0');
INSERT INTO CareTaker VALUES ('Lexie', '0');
INSERT INTO CareTaker VALUES ('Wilbert', '0');
INSERT INTO CareTaker VALUES ('Aurie', '0');
INSERT INTO CareTaker VALUES ('Belita', '0');
INSERT INTO CareTaker VALUES ('Cristobal', '0');
INSERT INTO CareTaker VALUES ('Alta', '0');
INSERT INTO CareTaker VALUES ('Earlie', '0');
INSERT INTO CareTaker VALUES ('Tatum', '0');
INSERT INTO CareTaker VALUES ('Decca', '0');
INSERT INTO CareTaker VALUES ('Thorstein', '0');
INSERT INTO CareTaker VALUES ('Carlin', '0');
INSERT INTO CareTaker VALUES ('Rodina', '0');
INSERT INTO CareTaker VALUES ('Byrom', '0');
INSERT INTO CareTaker VALUES ('Phillie', '0');
INSERT INTO CareTaker VALUES ('Bernete', '0');
INSERT INTO CareTaker VALUES ('Rachael', '0');
INSERT INTO CareTaker VALUES ('Maurice', '0');
INSERT INTO CareTaker VALUES ('Carmina', '0');
INSERT INTO CareTaker VALUES ('Margi', '0');
INSERT INTO CareTaker VALUES ('Francklin', '0');
INSERT INTO CareTaker VALUES ('Leonanie', '0');
INSERT INTO CareTaker VALUES ('Doralynn', '0');
INSERT INTO CareTaker VALUES ('Wells', '0');
INSERT INTO CareTaker VALUES ('Bill', '0');
INSERT INTO CareTaker VALUES ('Peg', '0');
INSERT INTO CareTaker VALUES ('Dorthy', '0');
INSERT INTO CareTaker VALUES ('Cobbie', '0');
INSERT INTO CareTaker VALUES ('Tyson', '0');
INSERT INTO CareTaker VALUES ('Rosana', '0');
INSERT INTO CareTaker VALUES ('Pip', '0');
INSERT INTO CareTaker VALUES ('Nadine', '0');
INSERT INTO CareTaker VALUES ('Brana', '0');
INSERT INTO CareTaker VALUES ('Eberhard', '0');
INSERT INTO CareTaker VALUES ('Annice', '0');
INSERT INTO CareTaker VALUES ('Tiffy', '0');
INSERT INTO CareTaker VALUES ('Edin', '0');
INSERT INTO CareTaker VALUES ('Nicky', '0');
INSERT INTO CareTaker VALUES ('Emerson', '0');
INSERT INTO CareTaker VALUES ('Reina', '0');
INSERT INTO CareTaker VALUES ('Blake', '0');
INSERT INTO CareTaker VALUES ('Pepito', '0');
INSERT INTO CareTaker VALUES ('Car', '0');
INSERT INTO CareTaker VALUES ('Alisha', '0');
INSERT INTO CareTaker VALUES ('Chiarra', '0');
INSERT INTO CareTaker VALUES ('Richmond', '0');
INSERT INTO CareTaker VALUES ('Nerti', '0');
INSERT INTO CareTaker VALUES ('Cleve', '0');
INSERT INTO CareTaker VALUES ('Hubey', '0');
INSERT INTO CareTaker VALUES ('Alisun', '0');
INSERT INTO CareTaker VALUES ('Andonis', '0');
INSERT INTO CareTaker VALUES ('Harry', '0');
INSERT INTO CareTaker VALUES ('Rebekah', '0');
INSERT INTO CareTaker VALUES ('Alfonse', '0');
INSERT INTO CareTaker VALUES ('Reggis', '0');
INSERT INTO CareTaker VALUES ('Norah', '0');
INSERT INTO CareTaker VALUES ('Hulda', '0');
INSERT INTO CareTaker VALUES ('Bette-ann', '0');
INSERT INTO CareTaker VALUES ('Hart', '0');
INSERT INTO CareTaker VALUES ('Raleigh', '0');
INSERT INTO CareTaker VALUES ('Pietra', '0');
INSERT INTO CareTaker VALUES ('Odey', '0');
INSERT INTO CareTaker VALUES ('Queenie', '0');
INSERT INTO CareTaker VALUES ('Peyton', '0');
INSERT INTO CareTaker VALUES ('Adam', '0');
INSERT INTO CareTaker VALUES ('Paulie', '0');
INSERT INTO CareTaker VALUES ('Lucky', '0');
INSERT INTO CareTaker VALUES ('Gwendolin', '0');
INSERT INTO CareTaker VALUES ('Sloan', '0');
INSERT INTO CareTaker VALUES ('Frankie', '0');
INSERT INTO CareTaker VALUES ('Randie', '0');
INSERT INTO CareTaker VALUES ('Ulberto', '0');
INSERT INTO CareTaker VALUES ('Carmel', '0');
INSERT INTO CareTaker VALUES ('Cathy', '0');
INSERT INTO CareTaker VALUES ('Homer', '0');
INSERT INTO CareTaker VALUES ('Yolanthe', '0');
INSERT INTO CareTaker VALUES ('Axel', '0');
INSERT INTO CareTaker VALUES ('Lilllie', '0');
INSERT INTO CareTaker VALUES ('Richart', '0');
INSERT INTO CareTaker VALUES ('Felicio', '0');
INSERT INTO CareTaker VALUES ('Harriett', '0');
INSERT INTO CareTaker VALUES ('Kitti', '0');
INSERT INTO CareTaker VALUES ('Jerry', '0');
INSERT INTO CareTaker VALUES ('Rebe', '0');
INSERT INTO CareTaker VALUES ('Leelah', '0');
INSERT INTO CareTaker VALUES ('Ethe', '0');
INSERT INTO CareTaker VALUES ('Sol', '0');
INSERT INTO CareTaker VALUES ('Toby', '0');
INSERT INTO CareTaker VALUES ('Maddalena', '0');
INSERT INTO CareTaker VALUES ('Kare', '0');
INSERT INTO CareTaker VALUES ('Huntley', '0');
INSERT INTO CareTaker VALUES ('Trudy', '0');
INSERT INTO CareTaker VALUES ('Janey', '0');
INSERT INTO CareTaker VALUES ('Janek', '0');
INSERT INTO CareTaker VALUES ('Blondelle', '0');
INSERT INTO CareTaker VALUES ('Dannie', '0');
INSERT INTO CareTaker VALUES ('Alejandra', '0');
INSERT INTO CareTaker VALUES ('Yolane', '0');
INSERT INTO CareTaker VALUES ('Ad', '0');
INSERT INTO CareTaker VALUES ('Tully', '0');
INSERT INTO CareTaker VALUES ('Florina', '0');
INSERT INTO CareTaker VALUES ('Wit', '0');
INSERT INTO CareTaker VALUES ('Zelma', '0');
INSERT INTO CareTaker VALUES ('Merrielle', '0');
INSERT INTO CareTaker VALUES ('Rubin', '0');
INSERT INTO CareTaker VALUES ('Arlyne', '0');
INSERT INTO CareTaker VALUES ('Jocelyn', '0');
INSERT INTO CareTaker VALUES ('Quincey', '0');
INSERT INTO CareTaker VALUES ('Virgil', '0');
INSERT INTO CareTaker VALUES ('Morissa', '0');
INSERT INTO CareTaker VALUES ('Ame', '0');
INSERT INTO CareTaker VALUES ('Consuelo', '0');
INSERT INTO CareTaker VALUES ('Alisander', '0');
INSERT INTO CareTaker VALUES ('Avrit', '0');
INSERT INTO CareTaker VALUES ('Reed', '0');
INSERT INTO CareTaker VALUES ('Vita', '0');
INSERT INTO CareTaker VALUES ('Afton', '0');
INSERT INTO CareTaker VALUES ('Welsh', '0');
INSERT INTO CareTaker VALUES ('Isidoro', '0');
INSERT INTO CareTaker VALUES ('Cammi', '0');
INSERT INTO CareTaker VALUES ('Jeannie', '0');
INSERT INTO CareTaker VALUES ('Essa', '0');
INSERT INTO CareTaker VALUES ('Elroy', '0');
INSERT INTO CareTaker VALUES ('Nomi', '0');
INSERT INTO CareTaker VALUES ('Crystie', '0');
INSERT INTO CareTaker VALUES ('Dulsea', '0');
INSERT INTO CareTaker VALUES ('Arlin', '0');
INSERT INTO CareTaker VALUES ('Hiram', '0');
INSERT INTO CareTaker VALUES ('Stafford', '0');
INSERT INTO CareTaker VALUES ('Richard', '0');
INSERT INTO CareTaker VALUES ('Cele', '0');
INSERT INTO CareTaker VALUES ('Welbie', '0');
INSERT INTO CareTaker VALUES ('Albertine', '0');
INSERT INTO CareTaker VALUES ('Amata', '0');
INSERT INTO CareTaker VALUES ('Cher', '0');
INSERT INTO CareTaker VALUES ('Arturo', '0');
INSERT INTO CareTaker VALUES ('Chick', '0');
INSERT INTO CareTaker VALUES ('Germana', '0');
INSERT INTO CareTaker VALUES ('Hillyer', '0');
INSERT INTO CareTaker VALUES ('Galvan', '0');
INSERT INTO CareTaker VALUES ('Rayna', '0');
INSERT INTO CareTaker VALUES ('Manuel', '0');
INSERT INTO CareTaker VALUES ('Saxon', '0');
INSERT INTO CareTaker VALUES ('Lettie', '0');
INSERT INTO CareTaker VALUES ('Eamon', '0');
INSERT INTO CareTaker VALUES ('Hillard', '0');
INSERT INTO CareTaker VALUES ('Marlene', '0');
INSERT INTO CareTaker VALUES ('Jason', '0');
INSERT INTO CareTaker VALUES ('Anabelle', '0');
INSERT INTO CareTaker VALUES ('Brit', '0');
INSERT INTO CareTaker VALUES ('Florian', '0');
INSERT INTO CareTaker VALUES ('Mal', '0');
INSERT INTO CareTaker VALUES ('Rudolph', '0');
INSERT INTO CareTaker VALUES ('Melisa', '0');
INSERT INTO CareTaker VALUES ('Heall', '0');
INSERT INTO CareTaker VALUES ('Wiley', '0');
INSERT INTO CareTaker VALUES ('Fernande', '0');
INSERT INTO CareTaker VALUES ('Berty', '0');
INSERT INTO CareTaker VALUES ('Yule', '0');
INSERT INTO CareTaker VALUES ('Dukie', '0');
INSERT INTO CareTaker VALUES ('Karlens', '0');
INSERT INTO CareTaker VALUES ('Elle', '0');
INSERT INTO CareTaker VALUES ('Vaughan', '0');
INSERT INTO CareTaker VALUES ('Basile', '0');
INSERT INTO CareTaker VALUES ('Tonya', '0');
INSERT INTO CareTaker VALUES ('Nichols', '0');
INSERT INTO CareTaker VALUES ('Brody', '0');
INSERT INTO CareTaker VALUES ('Philis', '0');
INSERT INTO CareTaker VALUES ('Bertie', '0');
INSERT INTO CareTaker VALUES ('Issi', '0');
INSERT INTO CareTaker VALUES ('Florentia', '0');
INSERT INTO CareTaker VALUES ('Ludovika', '0');
INSERT INTO CareTaker VALUES ('Collen', '0');
INSERT INTO CareTaker VALUES ('Worden', '0');
INSERT INTO CareTaker VALUES ('Louella', '0');
INSERT INTO CareTaker VALUES ('Gregorius', '0');
INSERT INTO CareTaker VALUES ('Wesley', '0');
INSERT INTO CareTaker VALUES ('Merill', '0');
INSERT INTO CareTaker VALUES ('Dynah', '0');
INSERT INTO CareTaker VALUES ('Shari', '0');
INSERT INTO CareTaker VALUES ('Lamont', '0');
INSERT INTO CareTaker VALUES ('Hildagard', '0');
INSERT INTO CareTaker VALUES ('Arline', '0');
INSERT INTO CareTaker VALUES ('Malinde', '0');
INSERT INTO CareTaker VALUES ('Bob', '0');
INSERT INTO CareTaker VALUES ('Hedvig', '0');
INSERT INTO CareTaker VALUES ('Babbette', '0');
INSERT INTO CareTaker VALUES ('Giacopo', '0');
INSERT INTO CareTaker VALUES ('Brett', '0');
INSERT INTO CareTaker VALUES ('Jonah', '0');
INSERT INTO CareTaker VALUES ('Theda', '0');
INSERT INTO CareTaker VALUES ('Evita', '0');
INSERT INTO CareTaker VALUES ('Erinn', '0');
INSERT INTO CareTaker VALUES ('Emmi', '0');
INSERT INTO CareTaker VALUES ('Gloriane', '0');
INSERT INTO CareTaker VALUES ('Burton', '0');
INSERT INTO CareTaker VALUES ('Mendel', '0');
INSERT INTO CareTaker VALUES ('Horace', '0');
INSERT INTO CareTaker VALUES ('Kyla', '0');
INSERT INTO CareTaker VALUES ('Winna', '0');
INSERT INTO CareTaker VALUES ('Zebulen', '0');
INSERT INTO CareTaker VALUES ('Durand', '0');
INSERT INTO CareTaker VALUES ('Malia', '0');
INSERT INTO CareTaker VALUES ('Osmond', '0');
INSERT INTO CareTaker VALUES ('Falito', '0');
INSERT INTO CareTaker VALUES ('Lorelle', '0');
INSERT INTO CareTaker VALUES ('Grady', '0');
INSERT INTO CareTaker VALUES ('Trudie', '0');
INSERT INTO CareTaker VALUES ('Trish', '0');
INSERT INTO CareTaker VALUES ('Delly', '0');
INSERT INTO CareTaker VALUES ('Barney', '0');
INSERT INTO CareTaker VALUES ('Val', '0');
INSERT INTO CareTaker VALUES ('Anallise', '0');
INSERT INTO CareTaker VALUES ('Marshall', '0');
INSERT INTO CareTaker VALUES ('Myrilla', '0');
INSERT INTO CareTaker VALUES ('Leonora', '0');
INSERT INTO CareTaker VALUES ('Dannel', '0');
INSERT INTO CareTaker VALUES ('Carolyn', '0');
INSERT INTO CareTaker VALUES ('Samuele', '0');
INSERT INTO CareTaker VALUES ('Oswell', '0');
INSERT INTO CareTaker VALUES ('Amalita', '0');
INSERT INTO CareTaker VALUES ('Culley', '0');
INSERT INTO CareTaker VALUES ('Nikolas', '0');
INSERT INTO CareTaker VALUES ('Ritchie', '0');
INSERT INTO CareTaker VALUES ('Donielle', '0');
INSERT INTO CareTaker VALUES ('Maxi', '0');
INSERT INTO CareTaker VALUES ('Doralynne', '0');
INSERT INTO CareTaker VALUES ('Daren', '0');
INSERT INTO CareTaker VALUES ('Giffie', '0');
INSERT INTO CareTaker VALUES ('Rozelle', '0');
INSERT INTO CareTaker VALUES ('Pascal', '0');
INSERT INTO CareTaker VALUES ('Heinrick', '0');
INSERT INTO CareTaker VALUES ('Teodoor', '0');
INSERT INTO CareTaker VALUES ('Sasha', '0');
INSERT INTO CareTaker VALUES ('Clive', '0');
INSERT INTO CareTaker VALUES ('Morten', '0');
INSERT INTO CareTaker VALUES ('Agna', '0');
INSERT INTO CareTaker VALUES ('Torr', '0');
INSERT INTO CareTaker VALUES ('Liesa', '0');
INSERT INTO CareTaker VALUES ('Lammond', '0');
INSERT INTO CareTaker VALUES ('Laney', '0');
INSERT INTO CareTaker VALUES ('Karoly', '0');
INSERT INTO CareTaker VALUES ('Yank', '0');
INSERT INTO CareTaker VALUES ('Willdon', '0');
INSERT INTO CareTaker VALUES ('Dewitt', '0');
INSERT INTO CareTaker VALUES ('Beryle', '0');
INSERT INTO CareTaker VALUES ('Dorian', '0');
INSERT INTO CareTaker VALUES ('Lowell', '0');
INSERT INTO CareTaker VALUES ('Ezequiel', '0');
INSERT INTO CareTaker VALUES ('Nick', '0');
INSERT INTO CareTaker VALUES ('Armando', '0');
INSERT INTO CareTaker VALUES ('Carry', '0');
INSERT INTO CareTaker VALUES ('Antons', '0');
INSERT INTO CareTaker VALUES ('Dorisa', '0');
INSERT INTO CareTaker VALUES ('Redd', '0');
INSERT INTO CareTaker VALUES ('Rouvin', '0');
INSERT INTO CareTaker VALUES ('Wynny', '0');
INSERT INTO CareTaker VALUES ('Elka', '0');
INSERT INTO CareTaker VALUES ('Beatriz', '0');
INSERT INTO CareTaker VALUES ('Othelia', '0');
INSERT INTO CareTaker VALUES ('Sheila', '0');
INSERT INTO CareTaker VALUES ('Misti', '0');
INSERT INTO CareTaker VALUES ('Darryl', '0');
INSERT INTO CareTaker VALUES ('Lyda', '0');
INSERT INTO CareTaker VALUES ('Doralin', '0');
INSERT INTO CareTaker VALUES ('Cristiano', '0');
INSERT INTO CareTaker VALUES ('Aggy', '0');
INSERT INTO CareTaker VALUES ('Iseabal', '0');
INSERT INTO CareTaker VALUES ('Alejandrina', '0');
INSERT INTO CareTaker VALUES ('Alfred', '0');
INSERT INTO CareTaker VALUES ('Sheela', '0');
INSERT INTO CareTaker VALUES ('Andie', '0');
INSERT INTO CareTaker VALUES ('Humfrid', '0');
INSERT INTO CareTaker VALUES ('Humbert', '0');

/*----------------------------------------------------*/
/* CareTakerEarnsSalary 100*/
INSERT INTO CareTakerEarnsSalary VALUES ('Raleigh', '2020-10-21', '1571.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Nomi', '2020-10-13', '2205.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Babbette', '2020-10-11', '3662.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Elka', '2020-10-03', '4826.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Earle', '2020-10-03', '3402.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Donia', '2020-10-25', '2466.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Maxi', '2020-10-28', '3098.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Dukie', '2020-10-16', '7373.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Hilarius', '2020-10-19', '2278.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Pascal', '2020-10-27', '3451.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Bell', '2020-10-18', '806.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Taber', '2020-11-10', '6913.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Cris', '2020-08-28', '4934.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Jeannie', '2020-10-10', '4678.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Cirilo', '2020-10-19', '5869.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Odey', '2020-04-22', '4089.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Cammi', '2020-10-03', '3449.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Wesley', '2020-09-02', '473.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Lorita', '2020-10-02', '3438.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Sigfrid', '2020-10-25', '1500.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Nicky', '2010-10-10', '7161.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Nichols', '2020-08-04', '1303.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Car', '2012-08-26', '6877.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Gloriane', '2020-10-02', '4300.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Earlie', '2017-06-12', '1140.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Byrom', '2020-11-29', '4563.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Fonz', '2020-06-23', '6138.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Dynah', '2012-12-16', '4269.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Jami', '2020-09-18', '5928.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Georgetta', '2020-12-29', '5636.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Allin', '2020-10-13', '4859.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Mortie', '2010-10-15', '2845.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Brit', '2010-12-26', '5228.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Judah', '2020-06-22', '6675.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Kordula', '2020-09-29', '2923.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Avram', '2014-09-24', '5207.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Morly', '2020-10-22', '4635.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Merill', '2020-10-29', '3526.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Adrian', '2017-11-17', '5767.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Brana', '2014-10-06', '7040.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Collen', '2020-10-11', '4747.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Tiffy', '2020-10-09', '2767.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Amery', '2020-04-04', '5852.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Ofelia', '2020-12-09', '6058.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Eamon', '2020-10-02', '1299.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Danie', '2020-10-09', '6556.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Leonora', '2012-06-12', '2026.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Eberhard', '2020-11-10', '1433.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Paulie', '2020-11-22', '2854.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Elsa', '2020-10-03', '608.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Jemie', '2012-10-16', '6116.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Crystie', '2020-10-12', '3221.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Jemmie', '2020-08-20', '3530.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Kirby', '2012-10-06', '1976.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Myrilla', '2020-10-06', '4521.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Rudolph', '2020-11-27', '2769.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Ernesta', '2014-12-18', '705.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Paulina', '2020-06-05', '785.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Pepe', '2020-10-10', '4200.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Lettie', '2020-12-19', '6389.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Agna', '2009-04-04', '5854.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Nickie', '2020-12-21', '6391.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Dacie', '2014-10-24', '1531.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Laney', '2014-10-18', '1769.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Harry', '2009-12-19', '3345.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Grant', '2020-10-02', '1322.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Lyle', '2020-10-10', '713.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Eddie', '2014-11-24', '4088.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Clea', '2020-10-25', '5010.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Amata', '2020-10-23', '3768.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Ritchie', '2020-10-11', '6031.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Dulsea', '2012-06-04', '6243.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Tremaine', '2020-08-28', '2560.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Cass', '2020-10-15', '5651.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Florina', '2012-10-08', '6503.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Dorisa', '2014-09-17', '6578.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Brett', '2020-08-29', '684.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Christie', '2017-04-08', '6813.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Dewitt', '2012-11-18', '6942.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Jerry', '2012-12-26', '5229.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Trudie', '2020-12-25', '3412.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Hayley', '2020-12-17', '2665.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Darryl', '2012-10-10', '7250.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Giuditta', '2020-10-28', '1311.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Melisa', '2020-09-06', '4494.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Adam', '2020-09-10', '7075.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Giffie', '2020-10-23', '3991.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Freeland', '2020-11-13', '1833.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Othelia', '2009-10-16', '6131.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Giorgia', '2020-12-25', '6212.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Bernete', '2020-04-05', '7393.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Ellswerth', '2020-04-05', '2178.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Carry', '2014-10-06', '1721.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Malinde', '2020-10-24', '5757.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Merrill', '2020-10-20', '1449.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Sharia', '2020-06-09', '5607.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Marshall', '2020-12-06', '3193.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Toby', '2009-10-25', '5303.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Dorian', '2020-11-07', '6271.00');
INSERT INTO CareTakerEarnsSalary VALUES ('Timmie', '2010-10-25', '4204.00');

/*----------------------------------------------------*/
/* FullTime 250*/
INSERT INTO FullTime VALUES ('Clemens');
INSERT INTO FullTime VALUES ('Georgetta');
INSERT INTO FullTime VALUES ('Tabor');
INSERT INTO FullTime VALUES ('Fern');
INSERT INTO FullTime VALUES ('Abby');
INSERT INTO FullTime VALUES ('Aron');
INSERT INTO FullTime VALUES ('Clementius');
INSERT INTO FullTime VALUES ('Gare');
INSERT INTO FullTime VALUES ('Cybil');
INSERT INTO FullTime VALUES ('Brendon');
INSERT INTO FullTime VALUES ('Petr');
INSERT INTO FullTime VALUES ('Frederica');
INSERT INTO FullTime VALUES ('Gwenni');
INSERT INTO FullTime VALUES ('Wood');
INSERT INTO FullTime VALUES ('Von');
INSERT INTO FullTime VALUES ('Eba');
INSERT INTO FullTime VALUES ('Avram');
INSERT INTO FullTime VALUES ('Nilson');
INSERT INTO FullTime VALUES ('Gran');
INSERT INTO FullTime VALUES ('Janos');
INSERT INTO FullTime VALUES ('Dion');
INSERT INTO FullTime VALUES ('Dalton');
INSERT INTO FullTime VALUES ('Eilis');
INSERT INTO FullTime VALUES ('Earle');
INSERT INTO FullTime VALUES ('Irma');
INSERT INTO FullTime VALUES ('Joseito');
INSERT INTO FullTime VALUES ('Frannie');
INSERT INTO FullTime VALUES ('Steven');
INSERT INTO FullTime VALUES ('Donia');
INSERT INTO FullTime VALUES ('Grant');
INSERT INTO FullTime VALUES ('Pepe');
INSERT INTO FullTime VALUES ('Elsa');
INSERT INTO FullTime VALUES ('Shelagh');
INSERT INTO FullTime VALUES ('Mahmoud');
INSERT INTO FullTime VALUES ('Bastian');
INSERT INTO FullTime VALUES ('Erin');
INSERT INTO FullTime VALUES ('Cordelia');
INSERT INTO FullTime VALUES ('Herbert');
INSERT INTO FullTime VALUES ('Hedy');
INSERT INTO FullTime VALUES ('Raven');
INSERT INTO FullTime VALUES ('Berenice');
INSERT INTO FullTime VALUES ('Giorgia');
INSERT INTO FullTime VALUES ('Courtenay');
INSERT INTO FullTime VALUES ('Lulita');
INSERT INTO FullTime VALUES ('Nataniel');
INSERT INTO FullTime VALUES ('Hayley');
INSERT INTO FullTime VALUES ('Maisey');
INSERT INTO FullTime VALUES ('Ruthanne');
INSERT INTO FullTime VALUES ('Giuditta');
INSERT INTO FullTime VALUES ('Garth');
INSERT INTO FullTime VALUES ('Dierdre');
INSERT INTO FullTime VALUES ('Clyde');
INSERT INTO FullTime VALUES ('Hymie');
INSERT INTO FullTime VALUES ('Timmie');
INSERT INTO FullTime VALUES ('Eulalie');
INSERT INTO FullTime VALUES ('Spike');
INSERT INTO FullTime VALUES ('Conant');
INSERT INTO FullTime VALUES ('Walker');
INSERT INTO FullTime VALUES ('Norby');
INSERT INTO FullTime VALUES ('Debbi');
INSERT INTO FullTime VALUES ('Uta');
INSERT INTO FullTime VALUES ('Briano');
INSERT INTO FullTime VALUES ('Flem');
INSERT INTO FullTime VALUES ('Dalt');
INSERT INTO FullTime VALUES ('Lorilyn');
INSERT INTO FullTime VALUES ('Tremaine');
INSERT INTO FullTime VALUES ('Dalston');
INSERT INTO FullTime VALUES ('Janina');
INSERT INTO FullTime VALUES ('Baron');
INSERT INTO FullTime VALUES ('Cirilo');
INSERT INTO FullTime VALUES ('Rafaello');
INSERT INTO FullTime VALUES ('Rossy');
INSERT INTO FullTime VALUES ('Allyson');
INSERT INTO FullTime VALUES ('Burke');
INSERT INTO FullTime VALUES ('Townie');
INSERT INTO FullTime VALUES ('Bax');
INSERT INTO FullTime VALUES ('Arel');
INSERT INTO FullTime VALUES ('Antoni');
INSERT INTO FullTime VALUES ('Clementine');
INSERT INTO FullTime VALUES ('Bernardina');
INSERT INTO FullTime VALUES ('Cass');
INSERT INTO FullTime VALUES ('Dacie');
INSERT INTO FullTime VALUES ('Bernetta');
INSERT INTO FullTime VALUES ('Ursola');
INSERT INTO FullTime VALUES ('Melvyn');
INSERT INTO FullTime VALUES ('Cary');
INSERT INTO FullTime VALUES ('Ellswerth');
INSERT INTO FullTime VALUES ('Binnie');
INSERT INTO FullTime VALUES ('Danie');
INSERT INTO FullTime VALUES ('Malcolm');
INSERT INTO FullTime VALUES ('Napoleon');
INSERT INTO FullTime VALUES ('Phineas');
INSERT INTO FullTime VALUES ('Farah');
INSERT INTO FullTime VALUES ('Loise');
INSERT INTO FullTime VALUES ('Tore');
INSERT INTO FullTime VALUES ('Fayre');
INSERT INTO FullTime VALUES ('Kylie');
INSERT INTO FullTime VALUES ('Natty');
INSERT INTO FullTime VALUES ('Cece');
INSERT INTO FullTime VALUES ('Kali');
INSERT INTO FullTime VALUES ('Harlen');
INSERT INTO FullTime VALUES ('Blake');
INSERT INTO FullTime VALUES ('Carolyn');
INSERT INTO FullTime VALUES ('Hilarius');
INSERT INTO FullTime VALUES ('Barr');
INSERT INTO FullTime VALUES ('Adrian');
INSERT INTO FullTime VALUES ('Jami');
INSERT INTO FullTime VALUES ('Jemie');
INSERT INTO FullTime VALUES ('Dina');
INSERT INTO FullTime VALUES ('Inessa');
INSERT INTO FullTime VALUES ('Freeland');
INSERT INTO FullTime VALUES ('Emalee');
INSERT INTO FullTime VALUES ('Earlie');
INSERT INTO FullTime VALUES ('Lexie');
INSERT INTO FullTime VALUES ('Doralynn');
INSERT INTO FullTime VALUES ('Karlens');
INSERT INTO FullTime VALUES ('Belita');
INSERT INTO FullTime VALUES ('Maurice');
INSERT INTO FullTime VALUES ('Christie');
INSERT INTO FullTime VALUES ('Issi');
INSERT INTO FullTime VALUES ('Dorian');
INSERT INTO FullTime VALUES ('Kordula');
INSERT INTO FullTime VALUES ('Humfrid');
INSERT INTO FullTime VALUES ('Rudolph');
INSERT INTO FullTime VALUES ('Leonanie');
INSERT INTO FullTime VALUES ('Morris');
INSERT INTO FullTime VALUES ('Nadine');
INSERT INTO FullTime VALUES ('Heinrick');
INSERT INTO FullTime VALUES ('Sheela');
INSERT INTO FullTime VALUES ('Korey');
INSERT INTO FullTime VALUES ('Amalita');
INSERT INTO FullTime VALUES ('Jonis');
INSERT INTO FullTime VALUES ('Saxon');
INSERT INTO FullTime VALUES ('Misti');
INSERT INTO FullTime VALUES ('Rosana');
INSERT INTO FullTime VALUES ('Pauly');
INSERT INTO FullTime VALUES ('Giffie');
INSERT INTO FullTime VALUES ('Paulina');
INSERT INTO FullTime VALUES ('Taber');
INSERT INTO FullTime VALUES ('Tedd');
INSERT INTO FullTime VALUES ('Yule');
INSERT INTO FullTime VALUES ('Myrilla');
INSERT INTO FullTime VALUES ('Philis');
INSERT INTO FullTime VALUES ('Mendel');
INSERT INTO FullTime VALUES ('Darryl');
INSERT INTO FullTime VALUES ('Aubree');
INSERT INTO FullTime VALUES ('Hannah');
INSERT INTO FullTime VALUES ('Doralin');
INSERT INTO FullTime VALUES ('Leonora');
INSERT INTO FullTime VALUES ('Elle');
INSERT INTO FullTime VALUES ('Dukie');
INSERT INTO FullTime VALUES ('Chrysa');
INSERT INTO FullTime VALUES ('Mortie');
INSERT INTO FullTime VALUES ('Fernande');
INSERT INTO FullTime VALUES ('Hildagard');
INSERT INTO FullTime VALUES ('Carlynne');
INSERT INTO FullTime VALUES ('Jacquetta');
INSERT INTO FullTime VALUES ('Malinde');
INSERT INTO FullTime VALUES ('Alisha');
INSERT INTO FullTime VALUES ('Judah');
INSERT INTO FullTime VALUES ('Richard');
INSERT INTO FullTime VALUES ('Sasha');
INSERT INTO FullTime VALUES ('Maxi');
INSERT INTO FullTime VALUES ('Chick');
INSERT INTO FullTime VALUES ('Dorthy');
INSERT INTO FullTime VALUES ('Issy');
INSERT INTO FullTime VALUES ('Lettie');
INSERT INTO FullTime VALUES ('Rodina');
INSERT INTO FullTime VALUES ('Brett');
INSERT INTO FullTime VALUES ('Car');
INSERT INTO FullTime VALUES ('Eddie');
INSERT INTO FullTime VALUES ('Dorisa');
INSERT INTO FullTime VALUES ('Nickie');
INSERT INTO FullTime VALUES ('Mal');
INSERT INTO FullTime VALUES ('Alfredo');
INSERT INTO FullTime VALUES ('Byrom');
INSERT INTO FullTime VALUES ('Suzi');
INSERT INTO FullTime VALUES ('Dewitt');
INSERT INTO FullTime VALUES ('Dynah');
INSERT INTO FullTime VALUES ('Brana');
INSERT INTO FullTime VALUES ('Vaughan');
INSERT INTO FullTime VALUES ('Rozelle');
INSERT INTO FullTime VALUES ('Abbott');
INSERT INTO FullTime VALUES ('Josefa');
INSERT INTO FullTime VALUES ('Wilbert');
INSERT INTO FullTime VALUES ('Bell');
INSERT INTO FullTime VALUES ('Amery');
INSERT INTO FullTime VALUES ('Jacobo');
INSERT INTO FullTime VALUES ('Konstance');
INSERT INTO FullTime VALUES ('Sandra');
INSERT INTO FullTime VALUES ('Aggy');
INSERT INTO FullTime VALUES ('Nicky');
INSERT INTO FullTime VALUES ('Hillyer');
INSERT INTO FullTime VALUES ('Agna');
INSERT INTO FullTime VALUES ('Berty');
INSERT INTO FullTime VALUES ('Brit');
INSERT INTO FullTime VALUES ('Marlene');
INSERT INTO FullTime VALUES ('Gianna');
INSERT INTO FullTime VALUES ('Decca');
INSERT INTO FullTime VALUES ('Markos');
INSERT INTO FullTime VALUES ('Pip');
INSERT INTO FullTime VALUES ('Kyla');
INSERT INTO FullTime VALUES ('Cele');
INSERT INTO FullTime VALUES ('Jemmie');
INSERT INTO FullTime VALUES ('Jordanna');
INSERT INTO FullTime VALUES ('Idaline');
INSERT INTO FullTime VALUES ('Essy');
INSERT INTO FullTime VALUES ('Alta');
INSERT INTO FullTime VALUES ('Bob');
INSERT INTO FullTime VALUES ('Hillard');
INSERT INTO FullTime VALUES ('Lammond');
INSERT INTO FullTime VALUES ('Pepito');
INSERT INTO FullTime VALUES ('Edin');
INSERT INTO FullTime VALUES ('Giacopo');
INSERT INTO FullTime VALUES ('Maurizio');
INSERT INTO FullTime VALUES ('Thorstein');
INSERT INTO FullTime VALUES ('Allen');
INSERT INTO FullTime VALUES ('Merrill');
INSERT INTO FullTime VALUES ('Bradan');
INSERT INTO FullTime VALUES ('Basile');
INSERT INTO FullTime VALUES ('Evita');
INSERT INTO FullTime VALUES ('Pascal');
INSERT INTO FullTime VALUES ('Beryle');
INSERT INTO FullTime VALUES ('Yank');
INSERT INTO FullTime VALUES ('Wilhelm');
INSERT INTO FullTime VALUES ('Marion');
INSERT INTO FullTime VALUES ('Worden');
INSERT INTO FullTime VALUES ('Phillie');
INSERT INTO FullTime VALUES ('Jason');
INSERT INTO FullTime VALUES ('Shari');
INSERT INTO FullTime VALUES ('Willow');
INSERT INTO FullTime VALUES ('Ezequiel');
INSERT INTO FullTime VALUES ('Ritchie');
INSERT INTO FullTime VALUES ('Kane');
INSERT INTO FullTime VALUES ('Florentia');
INSERT INTO FullTime VALUES ('Ike');
INSERT INTO FullTime VALUES ('Kirby');
INSERT INTO FullTime VALUES ('Ephrayim');
INSERT INTO FullTime VALUES ('Sheila');
INSERT INTO FullTime VALUES ('Antons');
INSERT INTO FullTime VALUES ('Nikolas');
INSERT INTO FullTime VALUES ('Iseabal');
INSERT INTO FullTime VALUES ('Erinn');
INSERT INTO FullTime VALUES ('Allin');
INSERT INTO FullTime VALUES ('Margi');
INSERT INTO FullTime VALUES ('Tonya');
INSERT INTO FullTime VALUES ('Cher');
INSERT INTO FullTime VALUES ('Catharine');
INSERT INTO FullTime VALUES ('Louella');
INSERT INTO FullTime VALUES ('Amata');

/*----------------------------------------------------*/
/* PartTime 250*/
INSERT INTO PartTime VALUES ('Chiarra');
INSERT INTO PartTime VALUES ('Richmond');
INSERT INTO PartTime VALUES ('Nerti');
INSERT INTO PartTime VALUES ('Cleve');
INSERT INTO PartTime VALUES ('Hubey');
INSERT INTO PartTime VALUES ('Alisun');
INSERT INTO PartTime VALUES ('Andonis');
INSERT INTO PartTime VALUES ('Harry');
INSERT INTO PartTime VALUES ('Rebekah');
INSERT INTO PartTime VALUES ('Alfonse');
INSERT INTO PartTime VALUES ('Reggis');
INSERT INTO PartTime VALUES ('Norah');
INSERT INTO PartTime VALUES ('Hulda');
INSERT INTO PartTime VALUES ('Bette-ann');
INSERT INTO PartTime VALUES ('Hart');
INSERT INTO PartTime VALUES ('Raleigh');
INSERT INTO PartTime VALUES ('Pietra');
INSERT INTO PartTime VALUES ('Odey');
INSERT INTO PartTime VALUES ('Queenie');
INSERT INTO PartTime VALUES ('Peyton');
INSERT INTO PartTime VALUES ('Adam');
INSERT INTO PartTime VALUES ('Paulie');
INSERT INTO PartTime VALUES ('Lucky');
INSERT INTO PartTime VALUES ('Gwendolin');
INSERT INTO PartTime VALUES ('Sloan');
INSERT INTO PartTime VALUES ('Frankie');
INSERT INTO PartTime VALUES ('Randie');
INSERT INTO PartTime VALUES ('Ulberto');
INSERT INTO PartTime VALUES ('Carmel');
INSERT INTO PartTime VALUES ('Cathy');
INSERT INTO PartTime VALUES ('Homer');
INSERT INTO PartTime VALUES ('Yolanthe');
INSERT INTO PartTime VALUES ('Axel');
INSERT INTO PartTime VALUES ('Lilllie');
INSERT INTO PartTime VALUES ('Richart');
INSERT INTO PartTime VALUES ('Felicio');
INSERT INTO PartTime VALUES ('Harriett');
INSERT INTO PartTime VALUES ('Kitti');
INSERT INTO PartTime VALUES ('Jerry');
INSERT INTO PartTime VALUES ('Rebe');
INSERT INTO PartTime VALUES ('Leelah');
INSERT INTO PartTime VALUES ('Ethe');
INSERT INTO PartTime VALUES ('Sol');
INSERT INTO PartTime VALUES ('Toby');
INSERT INTO PartTime VALUES ('Maddalena');
INSERT INTO PartTime VALUES ('Kare');
INSERT INTO PartTime VALUES ('Huntley');
INSERT INTO PartTime VALUES ('Trudy');
INSERT INTO PartTime VALUES ('Janey');
INSERT INTO PartTime VALUES ('Janek');
INSERT INTO PartTime VALUES ('Blondelle');
INSERT INTO PartTime VALUES ('Dannie');
INSERT INTO PartTime VALUES ('Alejandra');
INSERT INTO PartTime VALUES ('Yolane');
INSERT INTO PartTime VALUES ('Ad');
INSERT INTO PartTime VALUES ('Tully');
INSERT INTO PartTime VALUES ('Florina');
INSERT INTO PartTime VALUES ('Wit');
INSERT INTO PartTime VALUES ('Zelma');
INSERT INTO PartTime VALUES ('Merrielle');
INSERT INTO PartTime VALUES ('Rubin');
INSERT INTO PartTime VALUES ('Arlyne');
INSERT INTO PartTime VALUES ('Jocelyn');
INSERT INTO PartTime VALUES ('Quincey');
INSERT INTO PartTime VALUES ('Virgil');
INSERT INTO PartTime VALUES ('Morissa');
INSERT INTO PartTime VALUES ('Ame');
INSERT INTO PartTime VALUES ('Consuelo');
INSERT INTO PartTime VALUES ('Alisander');
INSERT INTO PartTime VALUES ('Avrit');
INSERT INTO PartTime VALUES ('Reed');
INSERT INTO PartTime VALUES ('Vita');
INSERT INTO PartTime VALUES ('Afton');
INSERT INTO PartTime VALUES ('Welsh');
INSERT INTO PartTime VALUES ('Isidoro');
INSERT INTO PartTime VALUES ('Cammi');
INSERT INTO PartTime VALUES ('Jeannie');
INSERT INTO PartTime VALUES ('Essa');
INSERT INTO PartTime VALUES ('Elroy');
INSERT INTO PartTime VALUES ('Nomi');
INSERT INTO PartTime VALUES ('Crystie');
INSERT INTO PartTime VALUES ('Dulsea');
INSERT INTO PartTime VALUES ('Arlin');
INSERT INTO PartTime VALUES ('Hiram');
INSERT INTO PartTime VALUES ('Stafford');
INSERT INTO PartTime VALUES ('Winna');
INSERT INTO PartTime VALUES ('Zebulen');
INSERT INTO PartTime VALUES ('Durand');
INSERT INTO PartTime VALUES ('Malia');
INSERT INTO PartTime VALUES ('Osmond');
INSERT INTO PartTime VALUES ('Falito');
INSERT INTO PartTime VALUES ('Lorelle');
INSERT INTO PartTime VALUES ('Grady');
INSERT INTO PartTime VALUES ('Trudie');
INSERT INTO PartTime VALUES ('Trish');
INSERT INTO PartTime VALUES ('Delly');
INSERT INTO PartTime VALUES ('Barney');
INSERT INTO PartTime VALUES ('Val');
INSERT INTO PartTime VALUES ('Anallise');
INSERT INTO PartTime VALUES ('Marshall');
INSERT INTO PartTime VALUES ('Harlen');
INSERT INTO PartTime VALUES ('Blake');
INSERT INTO PartTime VALUES ('Carolyn');
INSERT INTO PartTime VALUES ('Hilarius');
INSERT INTO PartTime VALUES ('Barr');
INSERT INTO PartTime VALUES ('Adrian');
INSERT INTO PartTime VALUES ('Jami');
INSERT INTO PartTime VALUES ('Jemie');
INSERT INTO PartTime VALUES ('Dina');
INSERT INTO PartTime VALUES ('Inessa');
INSERT INTO PartTime VALUES ('Freeland');
INSERT INTO PartTime VALUES ('Emalee');
INSERT INTO PartTime VALUES ('Earlie');
INSERT INTO PartTime VALUES ('Lexie');
INSERT INTO PartTime VALUES ('Doralynn');
INSERT INTO PartTime VALUES ('Karlens');
INSERT INTO PartTime VALUES ('Belita');
INSERT INTO PartTime VALUES ('Maurice');
INSERT INTO PartTime VALUES ('Christie');
INSERT INTO PartTime VALUES ('Issi');
INSERT INTO PartTime VALUES ('Dorian');
INSERT INTO PartTime VALUES ('Kordula');
INSERT INTO PartTime VALUES ('Humfrid');
INSERT INTO PartTime VALUES ('Rudolph');
INSERT INTO PartTime VALUES ('Leonanie');
INSERT INTO PartTime VALUES ('Morris');
INSERT INTO PartTime VALUES ('Nadine');
INSERT INTO PartTime VALUES ('Heinrick');
INSERT INTO PartTime VALUES ('Sheela');
INSERT INTO PartTime VALUES ('Korey');
INSERT INTO PartTime VALUES ('Amalita');
INSERT INTO PartTime VALUES ('Jonis');
INSERT INTO PartTime VALUES ('Saxon');
INSERT INTO PartTime VALUES ('Misti');
INSERT INTO PartTime VALUES ('Rosana');
INSERT INTO PartTime VALUES ('Pauly');
INSERT INTO PartTime VALUES ('Giffie');
INSERT INTO PartTime VALUES ('Paulina');
INSERT INTO PartTime VALUES ('Taber');
INSERT INTO PartTime VALUES ('Tedd');
INSERT INTO PartTime VALUES ('Yule');
INSERT INTO PartTime VALUES ('Myrilla');
INSERT INTO PartTime VALUES ('Philis');
INSERT INTO PartTime VALUES ('Mendel');
INSERT INTO PartTime VALUES ('Darryl');
INSERT INTO PartTime VALUES ('Aubree');
INSERT INTO PartTime VALUES ('Hannah');
INSERT INTO PartTime VALUES ('Doralin');
INSERT INTO PartTime VALUES ('Leonora');
INSERT INTO PartTime VALUES ('Elle');
INSERT INTO PartTime VALUES ('Dukie');
INSERT INTO PartTime VALUES ('Chrysa');
INSERT INTO PartTime VALUES ('Mortie');
INSERT INTO PartTime VALUES ('Fernande');
INSERT INTO PartTime VALUES ('Hildagard');
INSERT INTO PartTime VALUES ('Carlynne');
INSERT INTO PartTime VALUES ('Jacquetta');
INSERT INTO PartTime VALUES ('Malinde');
INSERT INTO PartTime VALUES ('Alisha');
INSERT INTO PartTime VALUES ('Judah');
INSERT INTO PartTime VALUES ('Richard');
INSERT INTO PartTime VALUES ('Sasha');
INSERT INTO PartTime VALUES ('Maxi');
INSERT INTO PartTime VALUES ('Chick');
INSERT INTO PartTime VALUES ('Dorthy');
INSERT INTO PartTime VALUES ('Issy');
INSERT INTO PartTime VALUES ('Lettie');
INSERT INTO PartTime VALUES ('Rodina');
INSERT INTO PartTime VALUES ('Brett');
INSERT INTO PartTime VALUES ('Car');
INSERT INTO PartTime VALUES ('Eddie');
INSERT INTO PartTime VALUES ('Dorisa');
INSERT INTO PartTime VALUES ('Nickie');
INSERT INTO PartTime VALUES ('Mal');
INSERT INTO PartTime VALUES ('Alfredo');
INSERT INTO PartTime VALUES ('Byrom');
INSERT INTO PartTime VALUES ('Suzi');
INSERT INTO PartTime VALUES ('Dewitt');
INSERT INTO PartTime VALUES ('Dynah');
INSERT INTO PartTime VALUES ('Brana');
INSERT INTO PartTime VALUES ('Vaughan');
INSERT INTO PartTime VALUES ('Rozelle');
INSERT INTO PartTime VALUES ('Abbott');
INSERT INTO PartTime VALUES ('Josefa');
INSERT INTO PartTime VALUES ('Wilbert');
INSERT INTO PartTime VALUES ('Bell');
INSERT INTO PartTime VALUES ('Amery');
INSERT INTO PartTime VALUES ('Jacobo');
INSERT INTO PartTime VALUES ('Konstance');
INSERT INTO PartTime VALUES ('Sandra');
INSERT INTO PartTime VALUES ('Aggy');
INSERT INTO PartTime VALUES ('Nicky');
INSERT INTO PartTime VALUES ('Hillyer');
INSERT INTO PartTime VALUES ('Agna');
INSERT INTO PartTime VALUES ('Berty');
INSERT INTO PartTime VALUES ('Brit');
INSERT INTO PartTime VALUES ('Marlene');
INSERT INTO PartTime VALUES ('Gianna');
INSERT INTO PartTime VALUES ('Decca');
INSERT INTO PartTime VALUES ('Markos');
INSERT INTO PartTime VALUES ('Pip');
INSERT INTO PartTime VALUES ('Kyla');
INSERT INTO PartTime VALUES ('Cele');
INSERT INTO PartTime VALUES ('Jemmie');
INSERT INTO PartTime VALUES ('Jordanna');
INSERT INTO PartTime VALUES ('Idaline');
INSERT INTO PartTime VALUES ('Essy');
INSERT INTO PartTime VALUES ('Alta');
INSERT INTO PartTime VALUES ('Bob');
INSERT INTO PartTime VALUES ('Hillard');
INSERT INTO PartTime VALUES ('Lammond');
INSERT INTO PartTime VALUES ('Pepito');
INSERT INTO PartTime VALUES ('Edin');
INSERT INTO PartTime VALUES ('Giacopo');
INSERT INTO PartTime VALUES ('Maurizio');
INSERT INTO PartTime VALUES ('Thorstein');
INSERT INTO PartTime VALUES ('Allen');
INSERT INTO PartTime VALUES ('Merrill');
INSERT INTO PartTime VALUES ('Bradan');
INSERT INTO PartTime VALUES ('Basile');
INSERT INTO PartTime VALUES ('Evita');
INSERT INTO PartTime VALUES ('Pascal');
INSERT INTO PartTime VALUES ('Beryle');
INSERT INTO PartTime VALUES ('Yank');
INSERT INTO PartTime VALUES ('Wilhelm');
INSERT INTO PartTime VALUES ('Marion');
INSERT INTO PartTime VALUES ('Worden');
INSERT INTO PartTime VALUES ('Phillie');
INSERT INTO PartTime VALUES ('Jason');
INSERT INTO PartTime VALUES ('Shari');
INSERT INTO PartTime VALUES ('Willow');
INSERT INTO PartTime VALUES ('Ezequiel');
INSERT INTO PartTime VALUES ('Ritchie');
INSERT INTO PartTime VALUES ('Kane');
INSERT INTO PartTime VALUES ('Florentia');
INSERT INTO PartTime VALUES ('Ike');
INSERT INTO PartTime VALUES ('Kirby');
INSERT INTO PartTime VALUES ('Ephrayim');
INSERT INTO PartTime VALUES ('Sheila');
INSERT INTO PartTime VALUES ('Antons');
INSERT INTO PartTime VALUES ('Nikolas');
INSERT INTO PartTime VALUES ('Iseabal');
INSERT INTO PartTime VALUES ('Erinn');
INSERT INTO PartTime VALUES ('Allin');
INSERT INTO PartTime VALUES ('Margi');
INSERT INTO PartTime VALUES ('Tonya');
INSERT INTO PartTime VALUES ('Cher');
INSERT INTO PartTime VALUES ('Catharine');
INSERT INTO PartTime VALUES ('Louella');
INSERT INTO PartTime VALUES ('Amata');

/*----------------------------------------------------*/
/* PartTimeIndicatesAvailability 100*/
INSERT INTO PartTimeIndicatesAvailability VALUES ('Jerry', '2019-07-12', '2019-06-19');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Rebe', '2020-01-14', '2020-08-03');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Leelah', '2020-01-28', '2021-07-01');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Ethe', '2019-08-07', '2020-11-07');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Sol', '2019-09-10', '2019-09-18');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Toby', '2019-08-13', '2020-12-05');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Maddalena', '2019-09-29', '2021-04-02');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Kare', '2019-09-11', '2021-06-20');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Huntley', '2019-07-03', '2020-12-23');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Trudy', '2019-08-29', '2021-02-03');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Janey', '2019-11-30', '2020-06-10');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Janek', '2020-02-29', '2021-01-17');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Sloan', '2019-12-14', '2020-07-12');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Frankie', '2020-01-24', '2021-02-17');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Randie', '2020-03-12', '2020-09-27');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Ulberto', '2019-08-02', '2021-05-11');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Carmel', '2019-04-27', '2019-10-21');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Cathy', '2019-12-02', '2021-07-09');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Homer', '2019-06-26', '2020-01-12');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Yolanthe', '2019-06-11', '2021-07-28');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Axel', '2019-10-08', '2020-12-19');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Lilllie', '2019-12-21', '2021-06-17');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Richart', '2019-04-07', '2019-08-26');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Felicio', '2019-05-28', '2021-04-18');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Harriett', '2020-01-01', '2020-10-13');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Kitti', '2020-03-30', '2020-10-08');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Rebekah', '2019-12-19', '2020-04-25');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Alfonse', '2019-12-23', '2019-11-28');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Reggis', '2019-06-06', '2020-11-06');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Norah', '2019-06-20', '2021-05-09');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Hulda', '2019-04-13', '2019-06-06');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Bette-ann', '2019-11-22', '2020-04-09');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Hart', '2019-11-10', '2020-04-04');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Raleigh', '2020-03-16', '2020-11-22');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Pietra', '2020-03-06', '2020-02-17');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Odey', '2019-12-18', '2021-05-23');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Queenie', '2020-02-03', '2019-07-21');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Peyton', '2019-06-19', '2019-11-11');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Adam', '2019-06-05', '2021-07-22');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Paulie', '2020-04-03', '2019-06-01');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Lucky', '2020-02-04', '2020-03-24');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Gwendolin', '2020-04-02', '2020-12-17');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Chiarra', '2019-04-16', '2020-05-25');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Richmond', '2019-06-21', '2021-10-29');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Nerti', '2019-12-15', '2019-11-30');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Cleve', '2019-09-27', '2020-06-14');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Hubey', '2019-11-15', '2021-05-11');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Alisun', '2020-03-29', '2021-04-16');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Andonis', '2019-07-09', '2019-12-10');
INSERT INTO PartTimeIndicatesAvailability VALUES ('Harry', '2019-06-04', '2021-05-10');

/*----------------------------------------------------*/
/* PetOwnerRegistersCreditCard 100*/
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Quincey', '9856884100909724', 'Quincey Mayor', '590', '2022-12-07');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Eberhard', '4086214032724664', 'Eberhard Cantera', '498', '2025-12-24');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Lyda', '1444301753777758', 'Lyda Manville', '504', '2028-06-06');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Frank', '4555992176730890', 'Frank Twinn', '904', '2024-10-18');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Odelia', '2131232759043528', 'Odelia Gianetti', '896', '2029-05-29');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Frasco', '9227892197399263', 'Frasco Sone', '375', '2025-07-19');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Belita', '5464106104537353', 'Catriona Shulem', '159', '2026-04-27');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Suzi', '3665857157582010', 'Suzi Corbridge', '760', '2028-01-23');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Julianna', '5567795071118172', 'Julianna Shiliton', '162', '2030-07-31');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Ansley', '4605609522185523', 'Ansley Bodman', '555', '2029-12-06');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Geno', '5461068707643449', 'Geno Crellim', '436', '2025-07-22');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Jobye', '8098964121371611', 'Jobye Curgenven', '758', '2024-03-19');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Andras', '3461160014896782', 'Andras Wheildon', '765', '2027-03-19');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Perkin', '4806562003723563', 'Perkin Artois', '759', '2028-12-14');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Freddy', '5649143672939560', 'Freddy Rens', '727', '2028-05-24');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Baxie', '8410264827957177', 'Baxie Deboo', '654', '2023-08-25');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Robin', '2276389234876044', 'Robin Taggart', '649', '2024-11-24');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Moritz', '5861762511328953', 'Moritz Tomasutti', '214', '2022-08-13');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Quincey', '8940686230876234', 'Gloriane Baskeyfied', '246', '2028-10-08');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Jami', '2754087036568450', 'Jami McCrae', '990', '2024-09-17');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Gare', '6727604930002412', 'Gare Coie', '620', '2025-07-08');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Yolanthe', '7051221480666114', 'Yolanthe Josskoviz', '392', '2024-06-17');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Jemima', '7002268881072300', 'Jemima Gaw', '394', '2024-09-02');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Dewitt', '1188328342302334', 'Dewitt Almond', '429', '2027-02-23');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Carin', '3554736669996268', 'Carin Goodlip', '579', '2029-10-15');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Kean', '4106268007384321', 'Kean Flanner', '153', '2024-05-11');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Quincey', '3018188553021994', 'Clint Janauschek', '332', '2026-10-27');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Regan', '2201418263605274', 'Regan Steiner', '269', '2028-03-08');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Emalee', '2194462677407700', 'Emalee Gaskell', '701', '2029-09-06');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Natty', '5422551007366825', 'Natty Shakelady', '889', '2029-07-14');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Florian', '7046886309576040', 'Florian Fancett', '488', '2023-04-27');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Delcine', '4480349296488300', 'Delcine Rolley', '359', '2022-11-03');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Duffy', '1360260785795060', 'Duffy Blunderfield', '317', '2028-02-12');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Cecil', '5239223334193502', 'Cecil Gear', '920', '2025-02-08');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Morten', '5470939161326223', 'Morten Beahan', '442', '2024-01-19');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Franciska', '1014383453333886', 'Franciska Mc Caughen', '952', '2026-02-27');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Mae', '8264828617648508', 'Mae Squier', '696', '2027-12-22');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Burgess', '9908148269542698', 'Burgess Pobjoy', '237', '2026-12-31');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Cris', '7074703224231335', 'Cris Woodwing', '724', '2023-08-23');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Rafaello', '3718787258782785', 'Rafaello Heathfield', '993', '2029-07-20');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Dav', '3991444827186047', 'Dav Cicconettii', '814', '2024-08-25');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Amalle', '4093252561271043', 'Amalle Twitty', '252', '2030-04-07');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Bibbie', '5234247863114239', 'Bibbie Ikin', '286', '2029-07-24');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Josefa', '8692418270045859', 'Josefa Crossley', '115', '2026-06-01');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Derby', '5890206831688260', 'Derby Matousek', '221', '2022-10-23');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Elizabeth', '5402888109513576', 'Elizabeth Gue', '100', '2023-04-14');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Fraze', '9576749572321241', 'Fraze Klosa', '868', '2027-01-29');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Slade', '5798605427286569', 'Slade Zanicchi', '301', '2025-11-06');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Beatriz', '3077397774516399', 'Beatriz Junkinson', '800', '2029-05-11');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Ricki', '1072636825691384', 'Ricki Halle', '404', '2027-12-08');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Benoit', '9589473302908152', 'Benoit Grcic', '387', '2023-07-13');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Worden', '6654053658173522', 'Worden Spargo', '211', '2024-04-19');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Janek', '2548972266747425', 'Janek Cafferty', '550', '2024-10-06');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Alica', '8997826564652739', 'Alica Lamke', '999', '2027-01-02');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Ethe', '9389060749097735', 'Ethe Halvosen', '365', '2025-09-09');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Hillard', '3347495058062937', 'Hillard Gallego', '660', '2030-01-17');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Dion', '6073543074880594', 'Dion Arnason', '349', '2027-09-03');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Raynor', '3165985171762176', 'Raynor Baffin', '294', '2024-06-15');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Gustavus', '3071120640585045', 'Gustavus Rist', '603', '2025-09-22');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Babb', '2767754387155079', 'Babb Gedney', '410', '2029-09-22');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Rebekah', '1723909034285180', 'Rebekah Middleditch', '160', '2027-04-19');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Germana', '2587066946224803', 'Germana Gianolo', '763', '2026-10-04');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Weston', '6358890343856690', 'Weston Peter', '310', '2030-06-18');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Marion', '4895398806489099', 'Marion Tomasz', '814', '2026-05-30');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Yolane', '3640039930848817', 'Yolane Whysall', '648', '2025-01-27');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Hillyer', '5176413878584873', 'Hillyer Mochan', '211', '2022-12-09');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Christalle', '5993567699317546', 'Christalle Tabor', '351', '2023-02-25');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Dannel', '2174016481316140', 'Dannel Bluck', '992', '2026-09-11');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Nealson', '7924417519019229', 'Nealson Reddin', '206', '2029-05-10');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Zorah', '4515840094835655', 'Zorah Halmkin', '541', '2023-09-24');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Kare', '4507287283455953', 'Kare de Verson', '925', '2022-09-10');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Maurice', '5182480933169188', 'Maurice Cattemull', '357', '2029-12-15');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Goldy', '6436635354608710', 'Goldy Cuming', '725', '2028-03-28');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Maddy', '5852343758544262', 'Maddy Hastilow', '533', '2030-03-31');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Monika', '5186782748445805', 'Monika Karpeev', '597', '2027-05-01');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Durand', '4103262596547196', 'Durand Chittie', '900', '2024-06-13');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Jonis', '2988844268149199', 'Jonis Jaycocks', '973', '2027-01-19');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Abdel', '4194362797987647', 'Abdel Edmead', '847', '2025-01-01');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Jodie', '8007919820871011', 'Jodie Litel', '521', '2028-06-08');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Rubia', '1346400255039383', 'Rubia Wilcocks', '945', '2026-01-03');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Alden', '4204470664308173', 'Alden Guillon', '586', '2022-12-01');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Delly', '7593066528601638', 'Delly MacGille', '684', '2029-06-01');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Elsa', '9527950277087272', 'Elsa McGann', '354', '2025-10-15');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Cornie', '8164421504549022', 'Cornie Lobb', '641', '2028-03-29');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Nichols', '8330707979599344', 'Nichols Lackington', '700', '2028-10-04');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Erwin', '3887284846821539', 'Erwin MacRory', '644', '2027-06-04');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Mickey', '5980346768158401', 'Mickey Niemetz', '449', '2023-06-14');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Mauricio', '3808935153384388', 'Mauricio McCrossan', '442', '2028-02-23');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Adrianne', '6800003027648417', 'Adrianne Code', '744', '2026-12-21');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Dud', '7298375290516328', 'Dud Farrimond', '250', '2029-03-07');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Ardelis', '8925175223360470', 'Ardelis Surpliss', '619', '2024-04-21');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Adrian', '1950744189176923', 'Adrian Grinstead', '371', '2024-11-13');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('La verne', '6120429499800367', 'La verne Broschke', '309', '2029-02-17');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Ertha', '5721198185954069', 'Ertha Ready', '624', '2022-12-07');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Kellyann', '1264593139908303', 'Kellyann Scoular', '292', '2028-01-30');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Jonah', '3992525725492980', 'Jonah Franklyn', '893', '2027-12-04');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Charlton', '4945260512544256', 'Charlton Heimes', '439', '2027-07-08');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Jacobo', '1243389565356416', 'Jacobo Mallya', '788', '2023-09-30');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Feodor', '5973579425795187', 'Feodor Eardley', '644', '2023-01-27');
INSERT INTO PetOwnerRegistersCreditCard VALUES ('Constantino', '5765214651003066', 'Constantino Beininck', '683', '2024-04-27');

/*----------------------------------------------------*/
/* CareTakerCatersPetCategory 500*/
INSERT INTO CareTakerCatersPetCategory VALUES ('Clemens', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Georgetta', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tabor', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Fern', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Abby', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Aron', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Clementius', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Gare', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cybil', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Brendon', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Petr', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Frederica', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Gwenni', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wood', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Von', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Eba', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Avram', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nilson', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Gran', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Janos', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dion', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dalton', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Eilis', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Earle', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Irma', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Joseito', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Frannie', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Steven', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Donia', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Grant', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Pepe', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Elsa', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Shelagh', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Mahmoud', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bastian', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Erin', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cordelia', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Herbert', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hedy', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Raven', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Berenice', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Giorgia', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Courtenay', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lulita', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nataniel', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hayley', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Maisey', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ruthanne', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Giuditta', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Garth', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dierdre', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Clyde', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hymie', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Timmie', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Eulalie', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Spike', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Conant', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Walker', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Norby', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Debbi', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Uta', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Briano', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Flem', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dalt', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lorilyn', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tremaine', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dalston', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Janina', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Baron', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cirilo', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rafaello', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rossy', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Allyson', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Burke', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Townie', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bax', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Arel', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Antoni', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Clementine', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bernardina', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cass', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dacie', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bernetta', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ursola', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Melvyn', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cary', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ellswerth', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Binnie', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Danie', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Malcolm', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Napoleon', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Phineas', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Farah', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Loise', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tore', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Fayre', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kylie', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Natty', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cece', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kali', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Waverley', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Diena', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hunter', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Darnell', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Idaline', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kimberley', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jacobo', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lyle', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Clea', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ram', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kordula', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bell', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Freeland', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Roderigo', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Genny', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jordanna', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Algernon', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tedd', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Palm', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lorita', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hedwiga', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Markos', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jerri', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('El', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Konstance', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Allin', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Allen', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Etienne', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Adrian', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Valencia', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Waylen', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jere', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ephrayim', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Barr', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Issy', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Christie', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cris', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lars', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Salvador', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Monika', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Goldy', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lorry', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hannah', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Adrienne', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bron', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kirby', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jonis', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Oralie', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Josefa', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Adoree', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Packston', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kane', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wade', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Mae', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sigfrid', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rhys', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Morris', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Essy', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Aubree', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sharia', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Taber', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Mortie', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Amery', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Reinwald', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Gianna', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Laurence', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alfie', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Willow', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Edythe', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Micaela', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jemmie', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jami', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Morly', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jacquetta', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Freddy', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Pauly', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bradan', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ansley', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Celka', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alfredo', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rabbi', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Maureene', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Odo', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Harlen', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Maurizio', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dre', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Emalee', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Korey', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kay', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Chrysa', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rudie', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Mignon', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jemie', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ricki', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kinsley', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rodolfo', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Marion', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Zacharia', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ike', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tallia', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Catharine', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Inessa', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Vittoria', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wilhelm', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Abbott', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ofelia', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Merrill', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Paulina', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Krissy', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Judah', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sandra', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Loralyn', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tyler', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Suzi', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Mychal', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Eddie', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hilarius', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Caroljean', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ernesta', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Clarita', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Loree', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Fonz', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Duff', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Carlynne', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dina', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rasla', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nickie', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lexie', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wilbert', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Aurie', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Belita', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cristobal', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alta', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Earlie', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tatum', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Decca', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Thorstein', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Carlin', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rodina', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Byrom', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Phillie', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bernete', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rachael', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Maurice', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Carmina', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Margi', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Francklin', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Leonanie', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Doralynn', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wells', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bill', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Peg', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dorthy', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cobbie', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tyson', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rosana', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Pip', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nadine', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Brana', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Eberhard', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Annice', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tiffy', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Edin', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nicky', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Emerson', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Reina', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Blake', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Pepito', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Car', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alisha', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Chiarra', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Richmond', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nerti', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cleve', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hubey', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alisun', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Andonis', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Harry', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rebekah', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alfonse', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Reggis', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Norah', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hulda', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bette-ann', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hart', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Raleigh', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Pietra', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Odey', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Queenie', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Peyton', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Adam', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Paulie', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lucky', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Gwendolin', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sloan', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Frankie', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Randie', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ulberto', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Carmel', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cathy', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Homer', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Yolanthe', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Axel', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lilllie', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Richart', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Felicio', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Harriett', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kitti', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jerry', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rebe', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Leelah', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ethe', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sol', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Toby', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Maddalena', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kare', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Huntley', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Trudy', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Janey', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Janek', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Blondelle', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dannie', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alejandra', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Yolane', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ad', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tully', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Florina', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wit', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Zelma', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Merrielle', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rubin', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Arlyne', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jocelyn', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Quincey', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Virgil', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Morissa', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ame', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Consuelo', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alisander', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Avrit', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Reed', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Vita', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Afton', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Welsh', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Isidoro', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cammi', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jeannie', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Essa', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Elroy', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nomi', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Crystie', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dulsea', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Arlin', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hiram', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Stafford', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Richard', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cele', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Welbie', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Albertine', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Amata', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cher', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Arturo', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Chick', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Germana', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hillyer', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Galvan', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rayna', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Manuel', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Saxon', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lettie', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Eamon', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hillard', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Marlene', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jason', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Anabelle', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Brit', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Florian', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Mal', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rudolph', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Melisa', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Heall', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wiley', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Fernande', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Berty', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Yule', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dukie', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Karlens', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Elle', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Vaughan', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Basile', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Tonya', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nichols', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Brody', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Philis', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bertie', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Issi', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Florentia', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ludovika', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Collen', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Worden', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Louella', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Gregorius', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wesley', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Merill', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dynah', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Shari', 'Rabbits', '130.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lamont', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hildagard', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Arline', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Malinde', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Bob', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Hedvig', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Babbette', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Giacopo', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Brett', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Jonah', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Theda', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Evita', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Erinn', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Emmi', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Gloriane', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Burton', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Mendel', 'Sheep', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Horace', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Kyla', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Winna', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Zebulen', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Durand', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Malia', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Osmond', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Falito', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lorelle', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Grady', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Trudie', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Trish', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Delly', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Barney', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Val', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Anallise', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Marshall', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Myrilla', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Leonora', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dannel', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Carolyn', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Samuele', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Oswell', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Amalita', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Culley', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nikolas', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ritchie', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Donielle', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Maxi', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Doralynne', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Daren', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Giffie', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rozelle', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Pascal', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Heinrick', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Teodoor', 'Alpacas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sasha', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Clive', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Morten', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Agna', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Torr', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Liesa', 'Horses', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lammond', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Laney', 'Pigs', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Karoly', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Yank', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Willdon', 'Goldfish', '50.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dewitt', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Beryle', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dorian', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lowell', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Ezequiel', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Nick', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Armando', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Carry', 'Columbines', '180.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Antons', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Dorisa', 'Barb', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Redd', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Rouvin', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Wynny', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Elka', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Beatriz', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Othelia', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sheila', 'Goats', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Misti', 'Hedgehogs', '160.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Darryl', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Lyda', 'Guppy', '100.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Doralin', 'Fowl', '140.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Cristiano', 'Cattle', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Aggy', 'Chinchillas', '60.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Iseabal', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alejandrina', 'Ferrets', '110.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Alfred', 'Mosquitofish', '120.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Sheela', 'Cats', '150.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Andie', 'Koi', '70.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Humfrid', 'Rodents', '90.0');
INSERT INTO CareTakerCatersPetCategory VALUES ('Humbert', 'Goats', '60.0');

/*----------------------------------------------------*/
/* Pet 100*/
INSERT INTO Pet VALUES ('Quincey', 'Hendrika', '2009-04-23', 'F', 'definition', 'project', 'local', 'Sheep');
INSERT INTO Pet VALUES ('Romola', 'Sabine', '2013-07-14', 'F', 'uniform', '24 hour', 'Fully-configurable', 'Fowl');
INSERT INTO Pet VALUES ('Belita', 'Tadio', '2003-04-16', 'M', 'Reduced', 'monitoring', 'analyzer', 'Alpacas');
INSERT INTO Pet VALUES ('Allin', 'Ernesta', '2001-09-30', 'F', 'focus group', 'workforce', 'Synergistic', 'Koi');
INSERT INTO Pet VALUES ('Hildagard', 'Jania', '2012-08-17', 'F', 'Implemented', 'complexity', 'Future-proofed', 'Goats');
INSERT INTO Pet VALUES ('Hilarius', 'Marissa', '2002-07-11', 'M', 'access', 'optimal', 'mobile', 'Guppy');
INSERT INTO Pet VALUES ('Holly', 'Arden', '2000-05-08', 'F', 'non-volatile', 'time-frame', 'groupware', 'Hedgehogs');
INSERT INTO Pet VALUES ('Morissa', 'Imelda', '2002-08-19', 'F', 'toolset', 'Sharable', 'zero defect', 'Goats');
INSERT INTO Pet VALUES ('Hildagard', 'Germaine', '2008-08-12', 'F', 'static', 'product', 'Total', 'Goldfish');
INSERT INTO Pet VALUES ('Hildagard', 'Pattie', '2003-05-06', 'F', 'local area network', 'extranet', 'moratorium', 'Goldfish');
INSERT INTO Pet VALUES ('Tades', 'Bantock', '2006-01-30', 'M', 'maximized', 'Exclusive', 'Profound', 'Mosquitofish');
INSERT INTO Pet VALUES ('Holly', 'Matteucci', '2002-06-05', 'F', 'real-time', 'matrix', 'projection', 'Columbines');
INSERT INTO Pet VALUES ('Belita', 'Pepper', '2001-08-16', 'M', 'tertiary', 'Optimized', 'website', 'Sheep');
INSERT INTO Pet VALUES ('Allin', 'Lisetta', '2005-10-13', 'M', 'methodology', 'systematic', 'bifurcated', 'Alpacas');
INSERT INTO Pet VALUES ('Akim', 'Charmion', '2011-12-03', 'F', 'Synchronised', 'adapter', 'Fundamental', 'Ferrets');
INSERT INTO Pet VALUES ('Winny', 'Ashlan', '2002-05-20', 'F', 'open architecture', 'Intuitive', 'portal', 'Sheep');
INSERT INTO Pet VALUES ('Morissa', 'Andy', '2000-10-11', 'F', 'hybrid', 'open architecture', 'Cross-platform', 'Cats');
INSERT INTO Pet VALUES ('Tremaine', 'Jenilee', '2012-06-27', 'F', 'system engine', 'contextually-based', 'Integrated', 'Cats');
INSERT INTO Pet VALUES ('Gianna', 'Renata', '2007-12-14', 'F', 'Mandatory', 'product', 'hub', 'Goldfish');
INSERT INTO Pet VALUES ('Romola', 'Kelley', '2001-02-06', 'M', 'archive', 'Organic', 'asynchronous', 'Mosquitofish');
INSERT INTO Pet VALUES ('Gianna', 'Ulrike', '2006-09-27', 'F', 'Programmable', 'composite', 'Object-based', 'Fowl');
INSERT INTO Pet VALUES ('Winny', 'Margrie', '2009-06-06', 'M', 'internet solution', 'matrices', 'customer loyalty', 'Alpacas');
INSERT INTO Pet VALUES ('Belita', 'Laure', '2013-10-09', 'F', 'responsive', 'foreground', 'Synergized', 'Sheep');
INSERT INTO Pet VALUES ('Romola', 'Lomath', '2001-12-26', 'M', 'hardware', 'Secured', 'Automated', 'Cattle');
INSERT INTO Pet VALUES ('Akim', 'Alys', '2014-09-09', 'M', 'Integrated', 'intermediate', 'open system', 'Columbines');
INSERT INTO Pet VALUES ('Allin', 'Brewer', '2000-05-11', 'M', 'knowledge base', 'logistical', 'moratorium', 'Goats');
INSERT INTO Pet VALUES ('Quincey', 'Judd', '2008-01-13', 'M', 'contextually-based', 'client-driven', 'actuating', 'Sheep');
INSERT INTO Pet VALUES ('Winny', 'Job', '2006-07-05', 'M', 'logistical', 'systemic', 'Multi-tiered', 'Goats');
INSERT INTO Pet VALUES ('Allin', 'Evyn', '2005-05-22', 'M', 'extranet', 'Synergized', 'methodical', 'Dogs');
INSERT INTO Pet VALUES ('Tades', 'Corie', '2000-10-19', 'M', 'model', 'radical', 'product', 'Sheep');
INSERT INTO Pet VALUES ('Tades', 'Claretta', '2001-02-14', 'F', 'Polarised', 'Re-engineered', 'Compatible', 'Guppy');
INSERT INTO Pet VALUES ('Morissa', 'Reba', '2001-12-19', 'F', 'Graphical User Interface', 'multi-state', 'Self-enabling', 'Cattle');
INSERT INTO Pet VALUES ('Allin', 'Jacquelin', '2010-10-04', 'F', 'Profound', 'monitoring', 'Fundamental', 'Cats');
INSERT INTO Pet VALUES ('Akim', 'Solomon', '2009-04-21', 'M', 'Customer-focused', 'Reverse-engineered', 'Centralized', 'Pigs');
INSERT INTO Pet VALUES ('Allin', 'Scarface', '2003-06-20', 'M', 'leverage', 'Inverse', 'fault-tolerant', 'Pigs');
INSERT INTO Pet VALUES ('Tades', 'Bobbie', '2000-05-31', 'F', 'access', '3rd generation', 'Down-sized', 'Cats');
INSERT INTO Pet VALUES ('Akim', 'Jacob', '2000-12-27', 'M', 'alliance', 'Integrated', 'stable', 'Chinchillas');
INSERT INTO Pet VALUES ('Quincey', 'Fitz', '2005-08-13', 'M', 'Visionary', 'intranet', 'framework', 'Horses');
INSERT INTO Pet VALUES ('Hilarius', 'Crystal', '2014-09-03', 'M', 'multimedia', 'hierarchy', 'Reactive', 'Koi');
INSERT INTO Pet VALUES ('Gianna', 'Flexman', '2007-08-10', 'F', 'migration', 'stable', 'knowledge base', 'Columbines');
INSERT INTO Pet VALUES ('Holly', 'Cathrine', '2009-08-31', 'F', 'non-volatile', 'moratorium', 'actuating', 'Barb');
INSERT INTO Pet VALUES ('Quincey', 'Stollwerck', '2001-09-08', 'F', 'ability', 'cohesive', 'optimal', 'Dogs');
INSERT INTO Pet VALUES ('Hilarius', 'Anastasia', '2003-10-21', 'F', 'Reactive', 'Object-based', 'forecast', 'Pigs');
INSERT INTO Pet VALUES ('Romola', 'Penny', '2013-08-05', 'M', 'multi-tasking', 'circuit', 'challenge', 'Guppy');
INSERT INTO Pet VALUES ('Akim', 'Leechman', '2000-01-12', 'M', 'Operative', 'system engine', 'Open-architected', 'Cats');
INSERT INTO Pet VALUES ('Gianna', 'Theodosia', '2009-02-18', 'M', 'installation', 'intranet', 'bifurcated', 'Cats');
INSERT INTO Pet VALUES ('Allin', 'Honatsch', '2005-01-16', 'F', 'database', 'tangible', 'Switchable', 'Horses');
INSERT INTO Pet VALUES ('Gianna', 'Cacilie', '2002-01-26', 'F', 'bottom-line', 'neutral', 'uniform', 'Cattle');
INSERT INTO Pet VALUES ('Akim', 'Liliane', '2011-08-12', 'M', 'local', 'methodology', 'mobile', 'Cattle');
INSERT INTO Pet VALUES ('Romola', 'Ashlee', '2009-09-28', 'F', 'interface', 'User-centric', 'capacity', 'Goats');
INSERT INTO Pet VALUES ('Gianna', 'Modesty', '2013-04-05', 'F', 'systemic', 'Customizable', '5th generation', 'Rodents');
INSERT INTO Pet VALUES ('Belita', 'Melisande', '2014-05-20', 'M', 'architecture', 'Reverse-engineered', 'Synchronised', 'Koi');
INSERT INTO Pet VALUES ('Tremaine', 'Stirzaker', '2011-06-23', 'F', 'emulation', 'capability', 'Monitored', 'Cattle');
INSERT INTO Pet VALUES ('Belita', 'Jodee', '2000-11-11', 'F', 'zero administration', 'mission-critical', 'productivity', 'Barb');
INSERT INTO Pet VALUES ('Tades', 'Brigitte', '2012-02-13', 'M', 'help-desk', 'budgetary management', 'foreground', 'Sheep');
INSERT INTO Pet VALUES ('Morissa', 'Adela', '2009-01-06', 'F', 'open system', 'forecast', '3rd generation', 'Cats');
INSERT INTO Pet VALUES ('Belita', 'Catina', '2013-08-20', 'F', 'initiative', 'attitude', 'multi-state', 'Columbines');
INSERT INTO Pet VALUES ('Akim', 'Aigneis', '2012-05-13', 'M', 'Expanded', 'Mandatory', 'parallelism', 'Chinchillas');
INSERT INTO Pet VALUES ('Allin', 'Ferdie', '2006-04-11', 'M', 'fault-tolerant', 'Cloned', 'adapter', 'Hedgehogs');
INSERT INTO Pet VALUES ('Quincey', 'Cherry', '2012-02-14', 'F', 'Team-oriented', 'dynamic', 'functionalities', 'Barb');
INSERT INTO Pet VALUES ('Romola', 'Karry', '2006-08-18', 'F', 'fault-tolerant', 'exuding', 'Realigned', 'Mosquitofish');
INSERT INTO Pet VALUES ('Hildagard', 'Carlie', '2013-02-07', 'F', 'disintermediate', 'local', 'Extended', 'Ferrets');
INSERT INTO Pet VALUES ('Hilarius', 'Dorie', '2008-05-24', 'M', 'bifurcated', 'foreground', 'matrices', 'Sheep');
INSERT INTO Pet VALUES ('Hilarius', 'Estrella', '2005-11-18', 'F', 'capacity', 'algorithm', 'data-warehouse', 'Pigs');
INSERT INTO Pet VALUES ('Akim', 'Beryl', '2006-12-12', 'M', 'impactful', 'infrastructure', 'Multi-tiered', 'Koi');
INSERT INTO Pet VALUES ('Tades', 'Clo', '2014-04-02', 'F', 'system-worthy', 'flexibility', 'Mandatory', 'Sheep');
INSERT INTO Pet VALUES ('Hilarius', 'Sapshed', '2013-04-14', 'F', 'ability', 'Stand-alone', 'portal', 'Cats');
INSERT INTO Pet VALUES ('Allin', 'Hannie', '2007-10-29', 'F', 'forecast', 'Programmable', 'framework', 'Cats');
INSERT INTO Pet VALUES ('Gianna', 'Quintana', '2008-10-13', 'M', 'portal', 'local', 'frame', 'Barb');
INSERT INTO Pet VALUES ('Tades', 'Barty', '2014-05-24', 'M', 'scalable', 'Persevering', 'Progressive', 'Columbines');
INSERT INTO Pet VALUES ('Gianna', 'Rosana', '2011-11-04', 'M', 'optimal', 'methodology', 'bifurcated', 'Chinchillas');
INSERT INTO Pet VALUES ('Morissa', 'Borgesio', '2009-02-09', 'M', 'protocol', 'mobile', 'reciprocal', 'Guppy');
INSERT INTO Pet VALUES ('Gianna', 'Felicia', '2006-01-12', 'M', 'algorithm', 'attitude-oriented', 'motivating', 'Goats');
INSERT INTO Pet VALUES ('Tades', 'Liuka', '2004-05-12', 'F', 'bandwidth-monitored', 'Optional', 'Multi-lateral', 'Pigs');
INSERT INTO Pet VALUES ('Hildagard', 'Angele', '2009-01-27', 'F', 'composite', 'Diverse', 'emulation', 'Guppy');
INSERT INTO Pet VALUES ('Belita', 'Maure', '2007-11-15', 'F', 'Upgradable', 'Future-proofed', 'flexibility', 'Ferrets');
INSERT INTO Pet VALUES ('Quincey', 'Casey', '2008-08-07', 'F', 'Reduced', 'grid-enabled', 'array', 'Horses');
INSERT INTO Pet VALUES ('Hilarius', 'Rebeca', '2003-09-15', 'M', 'Synchronised', 'time-frame', 'Fully-configurable', 'Columbines');
INSERT INTO Pet VALUES ('Allin', 'Idell', '2005-10-26', 'F', 'zero defect', 'hub', 'reciprocal', 'Rodents');
INSERT INTO Pet VALUES ('Holly', 'Corinna', '2014-01-08', 'F', 'Multi-tiered', 'mobile', '3rd generation', 'Ferrets');
INSERT INTO Pet VALUES ('Holly', 'Inglebert', '2002-09-08', 'M', 'Universal', 'application', 'toolset', 'Hedgehogs');
INSERT INTO Pet VALUES ('Romola', 'Dorolice', '2007-06-30', 'F', 'orchestration', 'focus group', 'infrastructure', 'Hedgehogs');
INSERT INTO Pet VALUES ('Tades', 'Riobard', '2003-01-25', 'M', '3rd generation', 'Polarised', 'Automated', 'Cats');
INSERT INTO Pet VALUES ('Holly', 'Mallissa', '2005-04-29', 'F', 'content-based', 'Reactive', 'modular', 'Ferrets');
INSERT INTO Pet VALUES ('Tades', 'Devin', '2006-01-25', 'M', 'discrete', 'Innovative', 'Down-sized', 'Ferrets');
INSERT INTO Pet VALUES ('Gianna', 'Gracia', '2000-03-03', 'M', 'transitional', 'asynchronous', 'hierarchy', 'Guppy');
INSERT INTO Pet VALUES ('Gianna', 'Regan', '2013-12-17', 'M', 'contextually-based', 'matrix', 'orchestration', 'Columbines');
INSERT INTO Pet VALUES ('Hilarius', 'Clarine', '2008-05-09', 'F', '4th generation', 'website', 'open architecture', 'Hedgehogs');
INSERT INTO Pet VALUES ('Hildagard', 'Krissie', '2014-05-06', 'M', 'Polarised', 'open architecture', 'parallelism', 'Mosquitofish');
INSERT INTO Pet VALUES ('Hildagard', 'Hallede', '2002-08-25', 'F', '4th generation', 'Integrated', 'implementation', 'Koi');
INSERT INTO Pet VALUES ('Tades', 'Norman', '2005-09-14', 'M', 'internet solution', 'multi-tasking', 'function', 'Cats');
INSERT INTO Pet VALUES ('Holly', 'Sheerman', '2006-11-15', 'F', 'Visionary', 'solution', 'De-engineered', 'Barb');
INSERT INTO Pet VALUES ('Quincey', 'Dulcie', '2002-10-19', 'F', 'Right-sized', 'open system', 'throughput', 'Sheep');
INSERT INTO Pet VALUES ('Belita', 'Rollin', '2002-03-26', 'F', 'implementation', 'web-enabled', 'Robust', 'Horses');
INSERT INTO Pet VALUES ('Romola', 'Cherida', '2004-08-12', 'M', 'user-facing', 'solution', 'static', 'Ferrets');
INSERT INTO Pet VALUES ('Romola', 'Minetta', '2003-08-30', 'M', 'value-added', 'local area network', 'Mandatory', 'Horses');
INSERT INTO Pet VALUES ('Winny', 'Lopez', '2011-07-25', 'M', 'Implemented', 'coherent', 'success', 'Barb');
INSERT INTO Pet VALUES ('Romola', 'Fredson', '2009-06-19', 'M', 'encompassing', 'productivity', 'Multi-layered', 'Cattle');
INSERT INTO Pet VALUES ('Winny', 'Lissi', '2013-03-24', 'M', '24 hour', 'solution-oriented', 'Decentralized', 'Fowl');
INSERT INTO Pet VALUES ('Winny', 'Krissy', '2003-10-21', 'M', 'client-driven', 'access', 'value-added', 'Barb');

/*----------------------------------------------------*/
/* Job 40*/
INSERT INTO Job VALUES ('Conant', 'Belita', 'Maure', '2020-11-06', '2021-01-22', '2020-09-24', 'REVIEWED', '3.5', 'CREDITCARD', 'PTB', '0.0', 'Postural Control Treatment of Integu Body using Orthosis');
INSERT INTO Job VALUES ('Clementine', 'Belita', 'Catina', '2020-10-02', '2021-01-05', '2020-09-25', 'COMPLETED', null, 'CASH', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Ursola', 'Winny', 'Krissy', '2020-10-27', '2020-12-30', '2020-09-15', 'REVIEWED', '0.5', 'CASH', 'POD', '0.0', 'CT Scan of L Rib using Oth Contrast');
INSERT INTO Job VALUES ('Tallia', 'Quincey', 'Dulcie', '2020-10-16', '2021-01-19', '2020-09-07', 'COMPLETED', null, 'CREDITCARD', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Idaline', 'Tremaine', 'Jenilee', '2020-10-28', '2020-12-03', '2020-08-31', 'REVIEWED', '1.0', 'CREDITCARD', 'PTB', '0.0', 'CT Scan of Bi Verteb Art using Oth Contrast');
INSERT INTO Job VALUES ('Bell', 'Romola', 'Karry', '2020-11-17', '2021-01-10', '2020-09-21', 'COMPLETED', null, 'CREDITCARD', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Valencia', 'Hilarius', 'Rebeca', '2020-11-23', '2020-12-02', '2020-09-27', 'REVIEWED', '4.0', 'CREDITCARD', 'CTP', '0.0', 'Compression of Left Lower Leg using Pressure Dressing');
INSERT INTO Job VALUES ('Mae', 'Gianna', 'Cacilie', '2020-11-11', '2021-01-26', '2020-09-15', 'COMPLETED', null, 'CASH', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Edythe', 'Hildagard', 'Jania', '2020-11-06', '2020-11-30', '2020-09-18', 'REVIEWED', '0.5', 'CREDITCARD', 'POD', '0.0', 'Orofacial Myofunctional Treatment using AV Equipment');
INSERT INTO Job VALUES ('Maureene', 'Winny', 'Lopez', '2020-10-08', '2020-12-26', '2020-09-09', 'COMPLETED', null, 'CREDITCARD', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Korey', 'Holly', 'Arden', '2020-10-11', '2021-01-13', '2020-09-14', 'REVIEWED', '0.5', 'CREDITCARD', 'CTP', '0.0', 'Planar Nucl Med Imag of Bi Low Extrem using Technetium 99m');
INSERT INTO Job VALUES ('Mignon', 'Gianna', 'Theodosia', '2020-11-26', '2020-12-07', '2020-09-05', 'COMPLETED', null, 'CREDITCARD', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Freddy', 'Allin', 'Brewer', '2020-11-28', '2021-01-24', '2020-09-26', 'REVIEWED', '3.5', 'CREDITCARD', 'PTB', '0.0', 'Plain Radiography of Left Lacrimal Duct using H Osm Contrast');
INSERT INTO Job VALUES ('Odo', 'Quincey', 'Hendrika', '2020-10-09', '2021-01-16', '2020-09-12', 'COMPLETED', null, 'CASH', 'CTP', '0.0', null);
INSERT INTO Job VALUES ('Ansley', 'Akim', 'Charmion', '2020-11-24', '2021-01-21', '2020-09-16', 'REVIEWED', '0.0', 'CREDITCARD', 'PTB', '0.0', 'Removal of Cast on Right Finger');
INSERT INTO Job VALUES ('Freddy', 'Morissa', 'Imelda', '2020-11-28', '2021-01-03', '2020-09-26', 'COMPLETED', null, 'CREDITCARD', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Jami', 'Morissa', 'Imelda', '2020-10-23', '2021-01-25', '2020-09-05', 'REVIEWED', '3.0', 'CREDITCARD', 'POD', '0.0', 'CT Scan of Kidney Transplant using Oth Contrast');
INSERT INTO Job VALUES ('Rabbi', 'Hilarius', 'Marissa', '2020-10-16', '2020-12-24', '2020-09-04', 'COMPLETED', null, 'CASH', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Edythe', 'Morissa', 'Imelda', '2020-10-12', '2020-12-19', '2020-09-12', 'REVIEWED', '0.5', 'CASH', 'PTB', '0.0', 'Sensory/Processing Assess Integu Low Back/LE w Oth Equip');
INSERT INTO Job VALUES ('Ike', 'Allin', 'Ernesta', '2020-10-29', '2020-12-10', '2020-09-25', 'COMPLETED', null, 'CASH', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Ansley', 'Akim', 'Charmion', '2020-10-20', '2021-01-14', '2020-09-10', 'REVIEWED', '1.0', 'CASH', 'POD', '0.0', 'Coord/Dexterity Trmt Integu Up Back/UE w Orthosis');
INSERT INTO Job VALUES ('Inessa', 'Holly', 'Arden', '2020-11-11', '2020-12-09', '2020-09-14', 'COMPLETED', null, 'CREDITCARD', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Peg', 'Akim', 'Charmion', '2020-10-19', '2021-01-26', '2020-09-28', 'REVIEWED', '4.5', 'CASH', 'POD', '0.0', 'Fluoroscopy of Left Foot/Toe Joint using Other Contrast');
INSERT INTO Job VALUES ('Dorthy', 'Romola', 'Sabine', '2020-10-18', '2021-01-23', '2020-09-23', 'COMPLETED', null, 'CREDITCARD', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Hulda', 'Akim', 'Charmion', '2020-11-26', '2020-12-04', '2020-09-28', 'REVIEWED', '2.0', 'CREDITCARD', 'POD', '0.0', 'CT Scan of L Tibia/Fibula using L Osm Contrast');
INSERT INTO Job VALUES ('Felicio', 'Winny', 'Ashlan', '2020-10-26', '2020-12-30', '2020-09-24', 'COMPLETED', null, 'CREDITCARD', 'CTP', '0.0', null);
INSERT INTO Job VALUES ('Sol', 'Romola', 'Sabine', '2020-10-03', '2020-12-07', '2020-08-31', 'REVIEWED', '2.0', 'CREDITCARD', 'CTP', '0.0', 'MRI of Bi Low Extrem Vein using Oth Contrast');
INSERT INTO Job VALUES ('Jocelyn', 'Gianna', 'Renata', '2020-10-21', '2020-12-05', '2020-09-17', 'COMPLETED', null, 'CASH', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Jeannie', 'Allin', 'Ernesta', '2020-10-30', '2020-12-08', '2020-08-31', 'REVIEWED', '1.0', 'CASH', 'POD', '0.0', 'Beam Radiation of Soft Palate using Photons <1 MeV');
INSERT INTO Job VALUES ('Hiram', 'Akim', 'Charmion', '2020-11-03', '2020-12-14', '2020-09-27', 'COMPLETED', null, 'CREDITCARD', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Manuel', 'Hilarius', 'Marissa', '2020-11-06', '2021-01-12', '2020-09-23', 'REVIEWED', '1.0', 'CREDITCARD', 'POD', '0.0', 'Computerized Tomography (CT Scan) of Bi Pelvic Vein');
INSERT INTO Job VALUES ('Melisa', 'Holly', 'Arden', '2020-10-02', '2020-12-13', '2020-09-10', 'COMPLETED', null, 'CASH', 'CTP', '0.0', null);
INSERT INTO Job VALUES ('Vaughan', 'Holly', 'Arden', '2020-11-22', '2021-01-04', '2020-09-17', 'REVIEWED', '5.0', 'CASH', 'CTP', '0.0', 'Wound Mgmt Trmt Musculosk Up Back/UE w Electrotherap Equip');
INSERT INTO Job VALUES ('Osmond', 'Morissa', 'Imelda', '2020-11-23', '2020-11-30', '2020-09-05', 'COMPLETED', null, 'CREDITCARD', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Mendel', 'Quincey', 'Hendrika', '2020-11-17', '2020-12-23', '2020-09-03', 'REVIEWED', '1.5', 'CREDITCARD', 'POD', '0.0', 'Removal of Splint on Left Lower Arm');
INSERT INTO Job VALUES ('Brendon', 'Winny', 'Ashlan', '2020-11-11', '2021-01-17', '2020-09-21', 'COMPLETED', null, 'CASH', 'POD', '0.0', null);
INSERT INTO Job VALUES ('Debbi', 'Hildagard', 'Jania', '2020-11-25', '2020-12-28', '2020-09-13', 'REVIEWED', '1.5', 'CREDITCARD', 'CTP', '0.0', 'LDR Brachytherapy of Nose using Californium 252');
INSERT INTO Job VALUES ('Norby', 'Hildagard', 'Jania', '2020-10-17', '2021-01-13', '2020-09-12', 'COMPLETED', null, 'CASH', 'PTB', '0.0', null);
INSERT INTO Job VALUES ('Flem', 'Tremaine', 'Jenilee', '2020-10-12', '2020-12-26', '2020-09-21', 'REVIEWED', '2.5', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Dalt', 'Quincey', 'Hendrika', '2020-11-28', '2020-12-30', '2020-09-14', 'COMPLETED', null, 'CREDITCARD', 'POD', '0.0', null);

INSERT INTO Job VALUES ('Amata', 'Quincey', 'Stollwerck', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Nikolas', 'Allin', 'Evyn', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Iseabal', 'Tades', 'Devin', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Erinn', 'Quincey', 'Judd', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Allin', 'Akim', 'Alys', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Margi', 'Allin', 'Honatsch', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');

INSERT INTO Job VALUES ('Tabor', 'Belita', 'Rollin', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Frederica', 'Hildagard', 'Germaine', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Nataniel', 'Winny', 'Lissi', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');
INSERT INTO Job VALUES ('Maisey', 'Gianna', 'Modesty', '2020-01-02', '2020-11-01', '2020-01-01', 'REVIEWED', '5.0', 'CREDITCARD', 'POD', '0.0', 'Ultrasonography of Right Renal Artery');

UPDATE Job SET pousername = pousername;

/*----------------------------------------------------*/
/* FullTimeAppliesLeaves 50*/
INSERT INTO FullTimeAppliesLeaves VALUES ('Amata', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Nikolas', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Iseabal', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Erinn', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Allin', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Margi', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Tabor', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Frederica', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Nataniel', '2020-12-30');
INSERT INTO FullTimeAppliesLeaves VALUES ('Maisey', '2020-12-30');

/* END OF DATA INITIALISATION */

/* START OF DATA CHECK */
SELECT COUNT(*) FROM administrator;
SELECT COUNT(*) FROM PetOwner;
SELECT COUNT(*) FROM caretaker;
SELECT COUNT(*) FROM caretakercaterspetcategory;
SELECT COUNT(*) FROM caretakerearnssalary;
SELECT COUNT(*) FROM fulltime;
SELECT COUNT(*) FROM fulltimeappliesleaves;
SELECT COUNT(*) FROM job;
SELECT COUNT(*) FROM parttime;
SELECT COUNT(*) FROM parttimeindicatesavailability;
SELECT COUNT(*) FROM pet;
SELECT COUNT(*) FROM petcategory;
SELECT COUNT(*) FROM PetOwnerRegistersCreditCard;
/* END OF DATA CHECK */;
					   